using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Text;
using System;

namespace CIPP.Tests
{
    /// <summary>Consolidated shared helpers for all built-in test ports.</summary>
    public static partial class CippTestHelpers
    {
        /// <summary>Case-insensitive single-level property lookup (exact match first, then scan).</summary>
        public static bool TryProp(JsonElement el, string name, out JsonElement val)
        {
            if (el.ValueKind == JsonValueKind.Object)
            {
                if (el.TryGetProperty(name, out val)) return true;
                foreach (var p in el.EnumerateObject())
                {
                    if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
                    {
                        val = p.Value;
                        return true;
                    }
                }
            }
            val = default;
            return false;
        }

        /// <summary>The property element, or a default (ValueKind.Undefined) element when absent.</summary>
        public static JsonElement Prop(JsonElement el, string name)
            => TryProp(el, name, out var v) ? v : default;

        /// <summary>String value of a property, or null when absent/null. Non-strings are rendered.</summary>
        public static string? Str(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return null;
            return v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Null or JsonValueKind.Undefined => null,
                _ => v.GetRawText()
            };
        }

        /// <summary>Mirrors <c>$_.name -eq $true</c>: real JSON true, or the string "true"/"True".</summary>
        public static bool IsTrue(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return false;
            return v.ValueKind == JsonValueKind.True
                || (v.ValueKind == JsonValueKind.String
                    && string.Equals(v.GetString(), "true", StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>Mirrors <c>$_.name -eq 'value'</c> — case-insensitive string equality.</summary>
        public static bool StrEq(JsonElement el, string name, string value)
            => string.Equals(Str(el, name), value, StringComparison.OrdinalIgnoreCase);

        /// <summary>Truthy non-empty string, matching a PS <c>$_.x -and ...</c> guard on a string.</summary>
        public static bool HasText(JsonElement el, string name)
            => !string.IsNullOrEmpty(Str(el, name));

        /// <summary>Enumerate a property that is a JSON array (empty when absent/not an array).</summary>
        public static IEnumerable<JsonElement> Arr(JsonElement el, string name)
        {
            if (TryProp(el, name, out var v) && v.ValueKind == JsonValueKind.Array)
            {
                foreach (var i in v.EnumerateArray()) yield return i;
            }
        }

        /// <summary>True when the element is a non-empty JSON array (mirrors a PS truthy array check).</summary>
        public static bool Any(JsonElement arr)
            => arr.ValueKind == JsonValueKind.Array && arr.GetArrayLength() > 0;

        /// <summary>Enumerate an array element (empty when it is not an array).</summary>
        public static IEnumerable<JsonElement> Items(JsonElement arr)
        {
            if (arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var i in arr.EnumerateArray()) yield return i;
            }
        }

        /// <summary>Integer value of a property (number or numeric string), 0 when absent — as PS <c>[int]</c> coerces $null to 0.</summary>
        public static long Int(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return 0;
            if (v.ValueKind == JsonValueKind.Number)
                return v.TryGetInt64(out var l) ? l : (long)v.GetDouble();
            if (v.ValueKind == JsonValueKind.String
                && long.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var sl))
                return sl;
            return 0;
        }

        /// <summary>Sum an integer field over the array property <paramref name="arrayName"/>.</summary>
        public static long SumOver(JsonElement el, string arrayName, string field)
        {
            long total = 0;
            foreach (var item in Arr(el, arrayName)) total += Int(item, field);
            return total;
        }

        /// <summary>Render a JSON value as PowerShell string interpolation would (True/False, raw number, string, "" for null).</summary>
        public static string Cell(JsonElement v) => v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() ?? "",
            JsonValueKind.True => "True",
            JsonValueKind.False => "False",
            JsonValueKind.Number => v.GetRawText(),
            JsonValueKind.Null or JsonValueKind.Undefined => "",
            _ => v.GetRawText()
        }

        ;

        /// <summary>[math]::Round(v, 1) — banker's rounding, matching the PS default.</summary>
        public static double Round1(double v) => Math.Round(v, 1, MidpointRounding.ToEven);

        /// <summary>Rounded percentage of <paramref name="n"/> over <paramref name="d"/> (0 when d==0).</summary>
        public static double Pct(long n, long d) => d > 0 ? Round1((double)n / d * 100) : 0;

        /// <summary>Format a (already-rounded) number the way PS interpolates a double: "50", "66.7".</summary>
        public static string Fmt(double v) => v.ToString("0.#", CultureInfo.InvariantCulture);

        /// <summary>
        /// Build a UPN → record lookup (key lowercased), keeping records with a non-empty
        /// userPrincipalName. Last write wins, matching PS hashtable assignment.
        /// </summary>
        public static Dictionary<string, JsonElement> LookupByUpn(JsonElement arr)
        {
            var d = new Dictionary<string, JsonElement>(System.StringComparer.Ordinal);
            foreach (var e in Items(arr))
            {
                var upn = Str(e, "userPrincipalName");
                if (!string.IsNullOrEmpty(upn)) d[upn!.ToLowerInvariant()] = e;
            }
            return d;
        }

        /// <summary>userPrincipalName present, accountEnabled true, and any Enabled assigned plan.</summary>
        public static bool IsLicensedAny(JsonElement user)
        {
            if (!HasText(user, "userPrincipalName") || !IsTrue(user, "accountEnabled")) return false;
            foreach (var plan in Arr(user, "assignedPlans"))
                if (StrEq(plan, "capabilityStatus", "Enabled")) return true;
            return false;
        }

        /// <summary>userPrincipalName present, accountEnabled true, and an Enabled MicrosoftOffice plan.</summary>
        public static bool IsOfficeLicensed(JsonElement user)
        {
            if (!HasText(user, "userPrincipalName") || !IsTrue(user, "accountEnabled")) return false;
            foreach (var plan in Arr(user, "assignedPlans"))
                if (StrEq(plan, "service", "MicrosoftOffice") && StrEq(plan, "capabilityStatus", "Enabled")) return true;
            return false;
        }

        /// <summary>
        /// The 6-signal Copilot readiness score (tests 008/009). Each of the six boolean signals
        /// is worth one point. A default/absent element scores 0 (IsTrue is false on Undefined).
        /// </summary>
        public static int ReadinessScore(JsonElement r)
        {
            int s = 0;
            if (IsTrue(r, "hasCopilotLicenseAssigned")) s++;
            if (IsTrue(r, "onQualifiedUpdateChannel")) s++;
            if (IsTrue(r, "usesTeamsMeetings")) s++;
            if (IsTrue(r, "usesTeamsChat")) s++;
            if (IsTrue(r, "usesOutlookEmail")) s++;
            if (IsTrue(r, "usesOfficeDocs")) s++;
            return s;
        }

        /// <summary>Status string PS emits when a tenant lacks the required license (not one of the four core statuses).</summary>
        public const string Unlicensed = "Unlicensed";

        /// <summary>
        /// Mirrors <c>$_.name -eq $false</c>: real JSON false, or the string "false"/"False".
        /// A missing/null value is NOT equal to $false in PS (<c>$null -eq $false</c> is False), so
        /// absent → false here too.
        /// </summary>
        public static bool IsFalse(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return false;
            return v.ValueKind == JsonValueKind.False
                || (v.ValueKind == JsonValueKind.String
                    && string.Equals(v.GetString(), "false", StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>Case-insensitive membership, mirroring PS <c>$_.name -in @(...)</c>.</summary>
        public static bool InSet(JsonElement el, string name, params string[] set)
        {
            var s = Str(el, name);
            if (s == null) return false;
            foreach (var candidate in set)
                if (string.Equals(s, candidate, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>Length of an array property, mirroring PS <c>$_.x.Count</c> (0 when absent/not an array).</summary>
        public static int ArrayLen(JsonElement el, string name)
            => TryProp(el, name, out var v) && v.ValueKind == JsonValueKind.Array ? v.GetArrayLength() : 0;

        /// <summary>
        /// PS truthiness of a property used in an <c>-and</c> guard / <c>if ($_.x)</c>:
        /// array → length &gt; 0, string → non-empty, bool → its value, number → non-zero,
        /// null/undefined → false.
        /// </summary>
        public static bool Truthy(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return false;
            return v.ValueKind switch
            {
                JsonValueKind.Array => v.GetArrayLength() > 0,
                JsonValueKind.String => !string.IsNullOrEmpty(v.GetString()),
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.Number => v.TryGetDouble(out var d) && d != 0,
                JsonValueKind.Null or JsonValueKind.Undefined => false,
                _ => true
            };
        }

        /// <summary>
        /// The string values of an array property (each rendered via <see cref="Cell"/>). Handles the
        /// case where EXO returns a single scalar instead of an array (PS treats a scalar as a 1-item
        /// collection for iteration / <c>-join</c>).
        /// </summary>
        public static IEnumerable<string> StringValues(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) yield break;
            if (v.ValueKind == JsonValueKind.Array)
            {
                foreach (var i in v.EnumerateArray()) yield return Cell(i);
            }
            else if (v.ValueKind != JsonValueKind.Null && v.ValueKind != JsonValueKind.Undefined)
            {
                yield return Cell(v);
            }
        }

        /// <summary>Convenience: render a named property the way PS interpolation would.</summary>
        public static string CellOf(JsonElement el, string name) => Cell(Prop(el, name));

        // ── PS -like wildcard ─────────────────────────────────────────────────────
        /// <summary>Case-insensitive PS <c>-like</c>: <c>*</c> = any run, <c>?</c> = one char, whole-string anchored.</summary>
        public static bool Like(string? value, string pattern)
        {
            if (value == null) return false;
            var rx = "^" + Regex.Escape(pattern).Replace("\\*", ".*").Replace("\\?", ".") + "$";
            return Regex.IsMatch(value, rx, RegexOptions.IgnoreCase | RegexOptions.Singleline);
        }

        // ── no-data markdown (licensing is gated upstream by the engine via requiredCapabilities) ──
        /// <summary>The standard "licensed but no data yet" Skipped markdown the ORCA tests emit when the cache has no data.</summary>
        public const string DefenderNoDataMarkdown =
            "No data found in the database. Data collection for this tenant may not have completed yet - refresh the cache and try again.";

        /// <summary>The first record of an array, or a default (Undefined) element when empty (PS Select -First 1).</summary>
        public static JsonElement First(JsonElement arr)
        {
            foreach (var i in Items(arr)) return i;
            return default;
        }

        /// <summary>The first record of an array, or null when empty — for callers that null-check.</summary>
        public static JsonElement? FirstOrNull(JsonElement arr)
        {
            foreach (var i in Items(arr)) return i;
            return null;
        }

        // ── PS truthiness and boolean comparison ───────────────────────────────────
        /// <summary>
        /// PowerShell <c>[bool]</c> cast: $null→false; bool→itself; NON-EMPTY string→true (incl.
        /// "false"/"0"); number→(≠0); array→empty false / single = element truthiness / many true;
        /// object→true. This is what <c>-not $_.x</c> negates.
        /// </summary>
        public static bool Truthy(JsonElement v)
        {
            switch (v.ValueKind)
            {
                case JsonValueKind.True: return true;
                case JsonValueKind.False: return false;
                case JsonValueKind.String: return !string.IsNullOrEmpty(v.GetString());
                case JsonValueKind.Number: return v.TryGetDouble(out var d) && d != 0;
                case JsonValueKind.Object: return true;
                case JsonValueKind.Array:
                    int len = v.GetArrayLength();
                    if (len == 0) return false;
                    if (len == 1) return Truthy(First(v));
                    return true;
                default: return false; // Null / Undefined
            }
        }

        /// <summary><c>-not $_.name</c> — the property's PS truthiness, negated.</summary>
        public static bool NotTruthyProp(JsonElement el, string name) => !Truthy(Prop(el, name));

        public static bool TruthyProp(JsonElement el, string name) => Truthy(Prop(el, name));

        /// <summary>
        /// Mirrors <c>if ($_.name -eq $true)</c>. Scalar: real true / string "true" (CI) / number 1.
        /// A JSON ARRAY reproduces PS collection filtering — <c>$array -eq $true</c> yields the matching
        /// elements and <c>if()</c> is truthy iff any element itself equals $true (e.g. a multi-valued
        /// EXO property like ExternalInOutlook that is not a scalar bool).
        /// </summary>
        public static bool EqTrue(JsonElement el, string name) => IsEqTrue(Prop(el, name));

        public static bool IsEqTrue(JsonElement v)
        {
            if (v.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in v.EnumerateArray()) if (IsEqTrue(e)) return true;
                return false;
            }
            return v.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.String => string.Equals(v.GetString(), "true", StringComparison.OrdinalIgnoreCase),
                JsonValueKind.Number => v.TryGetDouble(out var d) && d == 1,
                _ => false
            };
        }

        /// <summary>Mirrors <c>if ($_.name -eq $false)</c>: real false / string "false" (CI) / number 0, with the same array-filter semantics as <see cref="EqTrue"/>.</summary>
        public static bool EqFalse(JsonElement el, string name) => IsEqFalse(Prop(el, name));

        public static bool IsEqFalse(JsonElement v)
        {
            if (v.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in v.EnumerateArray()) if (IsEqFalse(e)) return true;
                return false;
            }
            return v.ValueKind switch
            {
                JsonValueKind.False => true,
                JsonValueKind.String => string.Equals(v.GetString(), "false", StringComparison.OrdinalIgnoreCase),
                JsonValueKind.Number => v.TryGetDouble(out var d) && d == 0,
                _ => false
            };
        }

        /// <summary><c>$a -eq $b</c> for two string fields (CI). Both must be present strings.</summary>
        public static bool StrEqStr(string? a, string? b)
            => a != null && b != null && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

        /// <summary><c>$_.name -in @(values)</c> — case-insensitive membership. Missing field → false.</summary>
        public static bool In(JsonElement el, string name, params string[] values)
        {
            var s = Str(el, name);
            if (s == null) return false;
            foreach (var candidate in values)
                if (string.Equals(s, candidate, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>PS <c>-match</c> — case-insensitive regex (substring unless anchored).</summary>
        public static bool Match(string? text, string pattern)
            => text != null && Regex.IsMatch(text, pattern, RegexOptions.IgnoreCase);

        /// <summary>Cell rendering of a property by name.</summary>
        public static string Cell(JsonElement el, string name) => Cell(Prop(el, name));

        /// <summary>
        /// PS <c>if ($x) { $x.Count } else { 0 }</c> for a property: 0 when falsy, else the array
        /// length (or 1 for a truthy scalar).
        /// </summary>
        public static int CountOrZero(JsonElement el, string name)
        {
            var v = Prop(el, name);
            if (!Truthy(v)) return 0;
            return v.ValueKind == JsonValueKind.Array ? v.GetArrayLength() : 1;
        }

        public static string Fmt(int n) => n.ToString(CultureInfo.InvariantCulture);

        /// <summary>
        /// PowerShell member-access projection with one level of flattening: for each source
        /// element that is an object with property <paramref name="name"/>, yield the property
        /// value — unrolling it when it is itself an array. Reproduces <c>$collection.prop</c>.
        /// </summary>
        public static IEnumerable<JsonElement> Project(IEnumerable<JsonElement> src, string name)
        {
            foreach (var el in src)
            {
                if (el.ValueKind != JsonValueKind.Object) continue;
                if (!TryProp(el, name, out var v)) continue;
                if (v.ValueKind == JsonValueKind.Array)
                {
                    foreach (var i in v.EnumerateArray()) yield return i;
                }
                else if (v.ValueKind != JsonValueKind.Null && v.ValueKind != JsonValueKind.Undefined)
                {
                    yield return v;
                }
            }
        }

        /// <summary>Case-insensitive substring match, mirroring a plain <c>-match 'literal'</c> on strings.</summary>
        public static bool ContainsCi(string? input, string needle)
            => input != null && input.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;

        /// <summary>Mirrors <c>$_.assignments -and $_.assignments.Count -gt 0</c>.</summary>
        public static bool HasAssignments(JsonElement policy)
            => TryProp(policy, "assignments", out var a)
               && a.ValueKind == JsonValueKind.Array
               && a.GetArrayLength() > 0;

        // ── ASR rule evaluation (shared by AppHard_06..14 and Macro_01..05) ───────
        /// <summary>
        /// Port of <c>Test-E8AsrRule</c>: verify a single Defender Attack Surface Reduction
        /// child setting is enabled (Block/Warn) and assigned. Reads IntuneConfigurationPolicies.
        /// Returns only Status + Markdown; metadata (Risk/Name/Category/impact) lives in the registry.
        /// </summary>
        public static CippTestResult EvaluateAsrRule(TenantData data, string ruleSettingId, string friendlyRule)
        {
            const string AsrRootId = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules";

            var configPolicies = data.Get("IntuneConfigurationPolicies");
            if (!Any(configPolicies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Intune Configuration Policies cached for this tenant.");
            }

            // AsrPolicies: platforms -like '*windows10*' AND technologies -like '*mdm*' AND the
            // settings expose the ASR root setting definition id.
            var asrPolicies = new List<JsonElement>();
            foreach (var p in Items(configPolicies))
            {
                if (!Like(Str(p, "platforms"), "*windows10*")) continue;
                if (!Like(Str(p, "technologies"), "*mdm*")) continue;

                var defIds = Project(Project(Arr(p, "settings"), "settingInstance"), "settingDefinitionId");
                bool hasAsr = defIds.Any(e => e.ValueKind == JsonValueKind.String
                    && string.Equals(e.GetString(), AsrRootId, StringComparison.OrdinalIgnoreCase));
                if (hasAsr) asrPolicies.Add(p);
            }

            if (asrPolicies.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No Defender Attack Surface Reduction policy is configured for Windows 10/11.");
            }

            // For each ASR policy, find the child setting for this rule and check its choice value
            // is a Block or Warn value; if so, the policy "matches". Then check assignment.
            int matchingTotal = 0;
            int matchingAssigned = 0;
            foreach (var p in asrPolicies)
            {
                var settingInstances = Project(Arr(p, "settings"), "settingInstance").ToList();
                var children = Project(Project(settingInstances, "groupSettingCollectionValue"), "children");
                var found = children.Where(c => c.ValueKind == JsonValueKind.Object
                    && string.Equals(Str(c, "settingDefinitionId"), ruleSettingId, StringComparison.OrdinalIgnoreCase));

                bool blockOrWarn = Project(Project(found, "choiceSettingValue"), "value")
                    .Any(v =>
                    {
                        var s = v.ValueKind == JsonValueKind.String ? v.GetString() : v.GetRawText();
                        return Like(s, "*_block") || Like(s, "*_warn");
                    });

                if (blockOrWarn)
                {
                    matchingTotal++;
                    if (HasAssignments(p)) matchingAssigned++;
                }
            }

            if (matchingTotal == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"No ASR policy enables `{friendlyRule}` (in Block or Warn mode).");
            }

            if (matchingAssigned > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"ASR rule `{friendlyRule}` is enabled and assigned in {matchingAssigned} policy/policies.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"ASR rule `{friendlyRule}` is configured but not assigned to any group/device.");
        }

        // ── date parsing (PatchApp_02) ───────────────────────────────────────────
        /// <summary>
        /// Parse an ISO datetime the way <c>[datetime]::Parse</c> does for comparison against a
        /// local-time threshold. Returns false when the value cannot be parsed (the PS path would
        /// throw and fail the whole test; unparseable Graph timestamps do not occur in practice).
        /// </summary>
        public static bool TryParseDate(string? value, out DateTime result)
            => DateTime.TryParse(value, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out result);

        /// <summary>Mirrors <c>$null -eq $_.name</c> — property absent, or present as JSON null.</summary>
        public static bool IsNullOrAbsent(JsonElement el, string name)
        {
            if (!CippTestHelpers.TryProp(el, name, out var v)) return true;
            return v.ValueKind == JsonValueKind.Null || v.ValueKind == JsonValueKind.Undefined;
        }

        // ── nested access ────────────────────────────────────────────────────────
        /// <summary>Walk a nested object path (case-insensitive at each level).</summary>
        public static bool TryPath(JsonElement el, out JsonElement val, params string[] path)
        {
            val = el;
            foreach (var seg in path)
            {
                if (!CippTestHelpers.TryProp(val, seg, out val)) { val = default; return false; }
            }
            return true;
        }

        /// <summary>String value at a nested path, or null when any segment is missing/null.</summary>
        public static string? PathStr(JsonElement el, params string[] path)
        {
            if (!TryPath(el, out var v, path)) return null;
            return v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Null or JsonValueKind.Undefined => null,
                _ => v.GetRawText()
            };
        }

        /// <summary>The element at a nested path is a non-empty JSON array (mirrors PS truthy array).</summary>
        public static bool PathTruthyArray(JsonElement el, params string[] path)
            => TryPath(el, out var v, path) && v.ValueKind == JsonValueKind.Array && v.GetArrayLength() > 0;

        /// <summary>The element at a nested path is truthy (PS <c>$_.a.b -and ...</c>).</summary>
        public static bool PathTruthy(JsonElement el, params string[] path)
            => TryPath(el, out var v, path) && Truthy(v);

        /// <summary>Mirrors <c>$_.a.b -contains 'value'</c>: nested array contains value (case-insensitive).</summary>
        public static bool PathArrayContainsCi(JsonElement el, string value, params string[] path)
        {
            if (!TryPath(el, out var v, path) || v.ValueKind != JsonValueKind.Array) return false;
            foreach (var i in v.EnumerateArray())
            {
                if (i.ValueKind == JsonValueKind.String
                    && string.Equals(i.GetString(), value, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        /// <summary>Mirrors <c>(@($_.a.b) | Where-Object { $_ -in $set }).Count -gt 0</c> (case-insensitive).</summary>
        public static bool PathArrayAnyIn(JsonElement el, ISet<string> set, params string[] path)
        {
            if (!TryPath(el, out var v, path) || v.ValueKind != JsonValueKind.Array) return false;
            foreach (var i in v.EnumerateArray())
            {
                if (i.ValueKind == JsonValueKind.String && set.Contains(i.GetString() ?? "")) return true;
            }
            return false;
        }

        // ── displayName list rendering ───────────────────────────────────────────
        /// <summary>Render a "- displayName" bullet list in cache order (PS join with `n).</summary>
        public static string BulletDisplayNames(IEnumerable<JsonElement> policies)
            => string.Join("\n", policies.Select(p => "- " + (CippTestHelpers.Str(p, "displayName") ?? "")));

        // ── privileged role / user resolution ────────────────────────────────────
        /// <summary>
        /// The Entra role TEMPLATE ids CIPP treats as privileged (mirrors
        /// Get-CIPPPrivilegedRoleTemplateIds -Set Privileged — 18 roles). Case-insensitive lookups.
        /// </summary>
        public static readonly HashSet<string> PrivRoleTemplateIds = new(StringComparer.OrdinalIgnoreCase)
        {
            "62e90394-69f5-4237-9190-012177145e10", // Global Administrator
            "194ae4cb-b126-40b2-bd5b-6091b380977d", // Security Administrator
            "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", // Application Administrator
            "e8611ab8-c189-46e8-94e1-60213ab1f814", // Privileged Role Administrator
            "29232cdf-9323-42fd-ade2-1d097af3e4de", // Exchange Administrator
            "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", // Conditional Access Administrator
            "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", // SharePoint Administrator
            "fe930be7-5e62-47db-91af-98c3a49a38b1", // User Administrator
            "729827e3-9c14-49f7-bb1b-9608f156bbb8", // Helpdesk Administrator
            "966707d0-3269-4727-9be2-8c3a10f19b9d", // Password Administrator
            "b0f54661-2d74-4c50-afa3-1ec803f12efe", // Billing Administrator
            "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", // Privileged Authentication Administrator
            "158c047a-c907-4556-b7ef-446551a6b5f7", // Cloud Application Administrator
            "c4e39bd9-1100-46d3-8c65-fb160da0071f", // Authentication Administrator
            "9f06204d-73c1-4d4c-880a-6edb90606fd8", // Azure AD Joined Device Local Administrator
            "17315797-102d-40b4-93e0-432062caca18", // Compliance Administrator
            "4a5d8f65-41da-4de4-8968-e035b65339cf", // Reports Reader
            "75941009-915a-4869-abe7-691bff18279e", // Skype for Business Administrator
        };

        /// <summary>The role's template id (case-insensitive read of roleTemplateId), or null.</summary>
        public static string? RoleTemplateId(JsonElement role) => CippTestHelpers.Str(role, "roleTemplateId");

        /// <summary>
        /// Roles from the cache filtered to CIPP's privileged set (mirrors
        /// Get-CippDbRole -IncludePrivilegedRoles). Empty when the Roles cache is absent/empty.
        /// </summary>
        public static List<JsonElement> PrivilegedRoles(TenantData data)
        {
            var result = new List<JsonElement>();
            foreach (var role in CippTestHelpers.Items(data.Get("Roles")))
            {
                var tid = RoleTemplateId(role);
                if (tid != null && PrivRoleTemplateIds.Contains(tid)) result.Add(role);
            }
            return result;
        }

        /// <summary>Template ids present among the supplied (privileged) roles.</summary>
        public static HashSet<string> TemplateIdSet(IEnumerable<JsonElement> roles)
        {
            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var r in roles)
            {
                var tid = RoleTemplateId(r);
                if (!string.IsNullOrEmpty(tid)) ids.Add(tid!);
            }
            return ids;
        }

        /// <summary>
        /// Active PIM role assignments (RoleAssignmentScheduleInstances) that are permanent:
        /// assignmentType 'Assigned', no endDateTime, and a principalId. Yields (roleDefinitionId,
        /// principalId) — roleDefinitionId is a role TEMPLATE id.
        /// </summary>
        public static IEnumerable<(string RoleDefId, string PrincipalId)> ActiveRoleAssignments(TenantData data)
        {
            foreach (var a in CippTestHelpers.Items(data.Get("RoleAssignmentScheduleInstances")))
            {
                if (!StrEq(a, "assignmentType", "Assigned")) continue;
                if (!IsNullOrAbsent(a, "endDateTime")) continue;
                var principalId = CippTestHelpers.Str(a, "principalId");
                if (string.IsNullOrEmpty(principalId)) continue;
                yield return (CippTestHelpers.Str(a, "roleDefinitionId") ?? "", principalId!);
            }
        }

        /// <summary>
        /// Resolve privileged user ids: union of the privileged roles' members (optionally only
        /// user-type members) with active PIM assignments to those roles' template ids.
        /// Mirrors the Admin_01/02/05 and MFA_07 resolution loops (ordinal id set).
        /// </summary>
        public static HashSet<string> PrivilegedUserIds(IReadOnlyCollection<JsonElement> privRoles, TenantData data, bool userMembersOnly)
        {
            var templateIds = TemplateIdSet(privRoles);
            var userIds = new HashSet<string>(StringComparer.Ordinal);

            foreach (var role in privRoles)
            {
                foreach (var m in CippTestHelpers.Arr(role, "members"))
                {
                    var id = CippTestHelpers.Str(m, "id");
                    if (string.IsNullOrEmpty(id)) continue;
                    if (userMembersOnly && !StrEq(m, "@odata.type", "#microsoft.graph.user")) continue;
                    userIds.Add(id!);
                }
            }

            foreach (var (roleDefId, principalId) in ActiveRoleAssignments(data))
            {
                if (templateIds.Contains(roleDefId)) userIds.Add(principalId);
            }

            return userIds;
        }

        // ── date parsing ─────────────────────────────────────────────────────────
        /// <summary>Parse an ISO datetime to UTC. False when unparseable.</summary>
        public static bool TryParseUtc(string? value, out DateTime result)
            => DateTime.TryParse(value, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out result);

        /// <summary>The identical Skipped message every EIDSCA test emits when its type is absent.</summary>
        public const string SkipMessage =
            "No data found in database. This may be due to missing required licenses or data collection not yet completed.";

        /// <summary>
        /// Walk a dotted property path case-insensitively. Returns a default (Undefined) element if
        /// any step is missing or is not an object — mirroring PS <c>$_.a.b.c</c> returning $null.
        /// </summary>
        public static JsonElement Path(JsonElement el, params string[] names)
        {
            var cur = el;
            foreach (var n in names)
            {
                if (cur.ValueKind != JsonValueKind.Object || !TryProp(cur, n, out var next)) return default;
                cur = next;
            }
            return cur;
        }

        /// <summary>Mirrors <c>$_.a.b -eq 'value'</c> — case-insensitive string equality at a path.</summary>
        public static bool PathStrEq(JsonElement el, string value, params string[] names)
            => string.Equals(PathStr(el, names), value, StringComparison.OrdinalIgnoreCase);

        /// <summary>Mirrors <c>$_.a.b -eq $true</c>: real JSON true or the string "true" at a path.</summary>
        public static bool PathIsTrue(JsonElement el, params string[] names)
        {
            var v = Path(el, names);
            return v.ValueKind == JsonValueKind.True
                || (v.ValueKind == JsonValueKind.String
                    && string.Equals(v.GetString(), "true", StringComparison.OrdinalIgnoreCase));
        }

        /// <summary>True when the element equals JSON false (or the string "false").</summary>
        public static bool IsFalseVal(JsonElement v)
            => v.ValueKind == JsonValueKind.False
            || (v.ValueKind == JsonValueKind.String
                && string.Equals(v.GetString(), "false", StringComparison.OrdinalIgnoreCase));

        /// <summary>Mirrors <c>$_.a.b -eq $false</c>: false at a path (missing → not false).</summary>
        public static bool IsFalseAt(JsonElement el, params string[] names) => IsFalseVal(Path(el, names));

        /// <summary>Render the value at a path the way PS interpolates it into a string ("" for absent).</summary>
        public static string PathCell(JsonElement el, params string[] names) => Cell(Path(el, names));

        /// <summary>
        /// Find an authentication method configuration by id (case-insensitive) within a policy
        /// record's <c>authenticationMethodConfigurations</c>. Default (Undefined) when not present,
        /// reproducing <c>… | Where-Object { $_.id -eq 'X' }</c> yielding $null.
        /// </summary>
        public static JsonElement FindMethodConfig(JsonElement policyRecord, string id)
        {
            foreach (var c in Arr(policyRecord, "authenticationMethodConfigurations"))
            {
                if (StrEq(c, "id", id)) return c;
            }
            return default;
        }

        /// <summary>True when an element is present (not Undefined/Null) — i.e. a config record was found.</summary>
        public static bool Found(JsonElement el)
            => el.ValueKind != JsonValueKind.Undefined && el.ValueKind != JsonValueKind.Null;

        /// <summary>Number of elements at an array path (0 when absent/not an array).</summary>
        public static int ArrCount(JsonElement el, params string[] names)
        {
            var v = Path(el, names);
            return v.ValueKind == JsonValueKind.Array ? v.GetArrayLength() : 0;
        }

        /// <summary>Case-insensitive membership, mirroring <c>$value -in @(options)</c>.</summary>
        public static bool StrIn(string? value, params string[] options)
        {
            foreach (var o in options)
            {
                if (string.Equals(value, o, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        /// <summary>
        /// Mirrors <c>$array -contains 'value'</c> for a string array property (case-insensitive).
        /// </summary>
        public static bool ArrayContainsCI(JsonElement el, string arrayName, string value)
        {
            foreach (var item in Arr(el, arrayName))
            {
                if (item.ValueKind == JsonValueKind.String
                    && string.Equals(item.GetString(), value, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        /// <summary>Join a string array property with a separator (mirrors <c>$array -join ', '</c>).</summary>
        public static string JoinArr(JsonElement el, string arrayName, string separator)
        {
            var parts = new List<string>();
            foreach (var item in Arr(el, arrayName)) parts.Add(Cell(item));
            return string.Join(separator, parts);
        }

        /// <summary>
        /// Look up a directory-settings value by name across every settings record's <c>values</c>
        /// array (mirrors <c>($Settings.values | Where-Object { $_.name -eq 'X' }).value</c>, which
        /// flattens the values of all records). Returns the first match's string value, or null.
        /// </summary>
        public static string? SettingValue(JsonElement settingsOrRecord, string name)
        {
            // Accept either the directorySetting ARRAY (EIDSCA callers) or a SINGLE setting record
            // (CIS password-rule callers pass FindPasswordRuleSetting's result). Both read values[].
            var records = settingsOrRecord.ValueKind == JsonValueKind.Array
                ? Items(settingsOrRecord)
                : new[] { settingsOrRecord };
            foreach (var rec in records)
            {
                foreach (var v in Arr(rec, "values"))
                {
                    if (StrEq(v, "name", name)) return Str(v, "value");
                }
            }
            return null;
        }

        /// <summary>Coerce a settings string value to int the way PS <c>[int]$SettingValue</c> does (null/empty → 0).</summary>
        public static int SettingInt(string? value)
        {
            if (string.IsNullOrEmpty(value)) return 0;
            if (long.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var l)) return (int)l;
            if (double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var d))
                return (int)Math.Round(d, MidpointRounding.ToEven);
            return 0;
        }

        /// <summary>Numeric value at a path (number or numeric string), 0 when absent — as PS coerces $null.</summary>
        public static double NumAt(JsonElement el, params string[] names)
        {
            var v = Path(el, names);
            if (v.ValueKind == JsonValueKind.Number) return v.TryGetDouble(out var d) ? d : 0;
            if (v.ValueKind == JsonValueKind.String
                && double.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var sd))
                return sd;
            return 0;
        }

        private static readonly StringComparison OIC = StringComparison.OrdinalIgnoreCase;

        /// <summary>
        /// Enumerate a value that the collector may have stored as a JSON array, a single JSON
        /// object, or a JSON string containing either. Mirrors the PS
        /// <c>if ($x -is [string]) { try { $x | ConvertFrom-Json } catch { @() } } else { $x }</c>
        /// pattern used for AssignedUsers / TermInfo / controlScores. Elements parsed out of a JSON
        /// string are cloned so they outlive the temporary document. Empty when null/absent/unparseable.
        /// </summary>
        public static IEnumerable<JsonElement> AsRecords(JsonElement el)
        {
            switch (el.ValueKind)
            {
                case JsonValueKind.Array:
                    foreach (var x in el.EnumerateArray()) yield return x;
                    break;
                case JsonValueKind.Object:
                    yield return el;
                    break;
                case JsonValueKind.String:
                    var s = el.GetString();
                    if (string.IsNullOrWhiteSpace(s)) yield break;
                    JsonDocument? doc = null;
                    try { doc = JsonDocument.Parse(s); } catch { doc = null; }
                    if (doc == null) yield break;
                    using (doc)
                    {
                        var root = doc.RootElement;
                        if (root.ValueKind == JsonValueKind.Array)
                            foreach (var x in root.EnumerateArray()) yield return x.Clone();
                        else if (root.ValueKind == JsonValueKind.Object)
                            yield return root.Clone();
                    }
                    break;
            }
        }

        /// <summary>Enumerate a named property with <see cref="AsRecords(JsonElement)"/> semantics.</summary>
        public static IEnumerable<JsonElement> RecordsOf(JsonElement el, string name)
            => TryProp(el, name, out var v) ? AsRecords(v) : Enumerable.Empty<JsonElement>();

        /// <summary>Mirrors <c>$_.name -like 'prefix*'</c> — case-insensitive prefix match; null → false.</summary>
        public static bool StartsWithCI(JsonElement el, string name, string prefix)
        {
            var s = Str(el, name);
            return s != null && s.StartsWith(prefix, OIC);
        }

        /// <summary>Mirrors <c>$_.name -in @(values)</c> — case-insensitive membership; null → false.</summary>
        public static bool InList(JsonElement el, string name, params string[] values)
        {
            var s = Str(el, name);
            if (s == null) return false;
            foreach (var v in values) if (string.Equals(s, v, OIC)) return true;
            return false;
        }

        /// <summary>Number value of a property (JSON number or numeric string), or null when absent/null/non-numeric.</summary>
        public static double? Num(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return null;
            if (v.ValueKind == JsonValueKind.Number) return v.GetDouble();
            if (v.ValueKind == JsonValueKind.String
                && double.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d))
                return d;
            return null;
        }

        /// <summary>Double value of a property, 0 when absent/null (mirrors PS <c>[double]$null</c> → 0).</summary>
        public static double Dbl(JsonElement el, string name) => Num(el, name) ?? 0d;

        /// <summary>True when the property exists and is neither JSON null nor undefined (PS <c>$null -ne $_.x</c>).</summary>
        public static bool HasValue(JsonElement el, string name)
            => TryProp(el, name, out var v) && v.ValueKind != JsonValueKind.Null && v.ValueKind != JsonValueKind.Undefined;

        /// <summary>[math]::Round(v, 0) — banker's rounding, matching the PS default.</summary>
        public static double Round0(double v) => Math.Round(v, 0, MidpointRounding.ToEven);

        /// <summary>Escape only pipes, matching the PS <c>-replace '\|', '\|'</c> the MFA reports apply. Null → "".</summary>
        public static string EscapePipe(string? s) => s == null ? "" : s.Replace("|", "\\|");

        /// <summary>
        /// Format an MFA-methods value the way the MFA reports do: "None" when the raw value is
        /// falsy (absent / null / empty string / empty array), otherwise the methods joined with
        /// ", " and normalised to friendly names. The caller applies any pipe-escaping.
        /// </summary>
        public static string FormatMfaMethods(JsonElement user)
        {
            if (!TryProp(user, "MFAMethods", out var el)) return "None";
            string joined;
            switch (el.ValueKind)
            {
                case JsonValueKind.String:
                    var s = el.GetString();
                    if (string.IsNullOrEmpty(s)) return "None";
                    try { using var d = JsonDocument.Parse(s); joined = JoinScalars(d.RootElement); }
                    catch { joined = s; }
                    break;
                case JsonValueKind.Array:
                    if (el.GetArrayLength() == 0) return "None";
                    joined = JoinScalars(el);
                    break;
                case JsonValueKind.Null:
                case JsonValueKind.Undefined:
                    return "None";
                default:
                    joined = Cell(el);
                    break;
            }
            return NormalizeMethodNames(joined);
        }

        private static string JoinScalars(JsonElement e)
            => e.ValueKind == JsonValueKind.Array
                ? string.Join(", ", e.EnumerateArray().Select(x => Cell(x)))
                : Cell(e);

        private static string NormalizeMethodNames(string s)
            => s.Replace("microsoftAuthenticator", "Authenticator")
                .Replace("phoneAuthentication", "Phone")
                .Replace("fido2", "FIDO2")
                .Replace("softwareOneTimePasscode", "Software OTP")
                .Replace("emailAuthentication", "Email")
                .Replace("windowsHelloForBusiness", "Windows Hello")
                .Replace("temporaryAccessPass", "Temp Pass");

        /// <summary>The "Protected By" cell shared by the MFA reports (verbose form used by 004).</summary>
        public static string ProtectionVerbose(JsonElement u)
        {
            if (StartsWithCI(u, "CoveredByCA", "Enforced")) return "Conditional Access";
            if (IsTrue(u, "CoveredBySD")) return "Security Defaults";
            if (InList(u, "PerUser", "Enforced", "Enabled")) return $"Per-User MFA ({Str(u, "PerUser")})";
            return "❌ None";
        }

        /// <summary>True when a user has no MFA enforcement by CA, Security Defaults, or per-user MFA.</summary>
        public static bool NotProtected(JsonElement u)
            => !StartsWithCI(u, "CoveredByCA", "Enforced")
               && !IsTrue(u, "CoveredBySD")
               && !InList(u, "PerUser", "Enforced", "Enabled");

        public const string GlobalAdministratorTemplateId = "62e90394-69f5-4237-9190-012177145e10";

        // ── PowerShell truthiness ──────────────────────────────────────────────────────────
        /// <summary>Mirror <c>[bool]$value</c> / <c>-not</c>: empty string is truthy (the EXO
        /// string-boolean gotcha), 0 / null / empty array / empty string are falsy.</summary>
        public static bool PsTruthy(JsonElement v) => v.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null or JsonValueKind.Undefined => false,
            JsonValueKind.String => !string.IsNullOrEmpty(v.GetString()),
            JsonValueKind.Number => v.TryGetDouble(out var d) && d != 0,
            JsonValueKind.Array => v.GetArrayLength() > 0,
            JsonValueKind.Object => true,
            _ => false,
        };

        /// <summary>Truthiness of a property (absent = falsy), mirroring PS <c>$_.x</c> in a boolean context.</summary>
        public static bool PsTruthyProp(JsonElement el, string name)
            => TryProp(el, name, out var v) && PsTruthy(v);

        /// <summary>
        /// Mirror <c>$_.name -eq &lt;bool&gt;</c> for a real JSON boolean or an EXO string boolean
        /// ("True"/"False"). Absent/other = not equal.
        /// </summary>
        public static bool BoolEq(JsonElement el, string name, bool expected)
        {
            if (!TryProp(el, name, out var v)) return false;
            return v.ValueKind switch
            {
                JsonValueKind.True => expected,
                JsonValueKind.False => !expected,
                JsonValueKind.String => bool.TryParse(v.GetString(), out var b) && b == expected,
                _ => false,
            };
        }

        // ── string ops ───────────────────────────────────────────────────────────────────
        /// <summary>PowerShell <c>-in</c> / <c>-contains</c> for a scalar string — case-insensitive.</summary>
        public static bool InListCI(string? value, params string[] options)
        {
            if (value == null) return false;
            foreach (var o in options)
                if (string.Equals(o, value, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>PowerShell <c>-like</c> wildcard match, case-insensitive. Null value never matches.</summary>
        public static bool LikeCI(string? value, string pattern)
        {
            if (value == null) return false;
            var rx = "^" + Regex.Escape(pattern).Replace("\\*", ".*").Replace("\\?", ".") + "$";
            return Regex.IsMatch(value, rx, RegexOptions.IgnoreCase | RegexOptions.Singleline);
        }

        /// <summary>PowerShell <c>-notlike</c> — negation of <see cref="LikeCI"/> (null value → true).</summary>
        public static bool NotLikeCI(string? value, string pattern) => !LikeCI(value, pattern);

        /// <summary>PowerShell <c>-match</c> (case-insensitive regex). Null value never matches.</summary>
        public static bool MatchCI(string? value, string pattern)
            => value != null && Regex.IsMatch(value, pattern, RegexOptions.IgnoreCase);

        /// <summary>
        /// Mirror PS <c>$_.field -and ($_.field.Count -gt 0)</c>: field present and non-empty. An
        /// array counts its length; a non-null scalar counts as one.
        /// </summary>
        public static bool CountGt0(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return false;
            if (v.ValueKind == JsonValueKind.Array) return v.GetArrayLength() > 0;
            return PsTruthy(v);
        }

        /// <summary>Length of an array property (0 when absent/not an array). Mirrors <c>($x | Measure-Object).Count</c> / <c>$x.Count</c>.</summary>
        public static int ArrayCount(JsonElement el, string name)
            => TryProp(el, name, out var v) && v.ValueKind == JsonValueKind.Array ? v.GetArrayLength() : 0;

        // ── role assembly (reproduces Get-CippDbRole) ──────────────────────────────────────
        /// <summary>
        /// The privileged directory-role records (Roles cache filtered to
        /// <see cref="PrivilegedRoleTemplateIds"/>). Reproduces
        /// <c>Get-CippDbRole -IncludePrivilegedRoles</c>: an empty result means either no Roles
        /// cache or no privileged roles matched (PowerShell's Where-Object yields $null in both).
        /// </summary>
        public static List<JsonElement> GetPrivilegedRoles(TenantData data)
        {
            var result = new List<JsonElement>();
            foreach (var r in Items(data.Get("Roles")))
            {
                var tid = Str(r, "roleTemplateId");
                if (tid != null && PrivRoleTemplateIds.Contains(tid)) result.Add(r);
            }
            return result;
        }

        /// <summary>PIM assignment with no expiry: <c>$null -eq endDateTime</c> (absent or JSON null).</summary>
        public static bool EndDateNull(JsonElement a)
            => !TryProp(a, "endDateTime", out var v) || v.ValueKind == JsonValueKind.Null;

        /// <summary>
        /// Privileged user ids = direct members of the privileged roles + active-permanent PIM
        /// assignments (assignmentType 'Assigned', no endDateTime) whose roleDefinitionId is one of
        /// the privileged templates. Matches Invoke-CippTestCIS_1_1_1 / _1_1_4 exactly (ordinal id
        /// set, as the PS HashSet[string] uses the default ordinal comparer).
        /// </summary>
        public static HashSet<string> CollectPrivilegedUserIds(TenantData data)
        {
            var roleIds = new HashSet<string>(StringComparer.Ordinal);
            var userIds = new HashSet<string>(StringComparer.Ordinal);

            foreach (var role in GetPrivilegedRoles(data))
            {
                var tid = Str(role, "roleTemplateId");
                if (!string.IsNullOrEmpty(tid)) roleIds.Add(tid!);
                foreach (var m in Arr(role, "members"))
                {
                    var mid = Str(m, "id");
                    if (!string.IsNullOrEmpty(mid)) userIds.Add(mid!);
                }
            }

            foreach (var a in Items(data.Get("RoleAssignmentScheduleInstances")))
            {
                var rdid = Str(a, "roleDefinitionId");
                if (!string.IsNullOrEmpty(rdid) && StrEq(a, "assignmentType", "Assigned")
                    && EndDateNull(a) && roleIds.Contains(rdid!))
                {
                    var pid = Str(a, "principalId");
                    if (!string.IsNullOrEmpty(pid)) userIds.Add(pid!);
                }
            }
            return userIds;
        }

        /// <summary>The first role record whose displayName is 'Global Administrator' (case-insensitive), or null.</summary>
        public static JsonElement? GlobalAdminRole(TenantData data)
        {
            foreach (var r in Items(data.Get("Roles")))
                if (StrEq(r, "displayName", "Global Administrator")) return r;
            return null;
        }

        /// <summary>
        /// Global Administrator member ids = direct GA members + active-permanent PIM assignments
        /// whose roleDefinitionId equals the GA role's roleTemplateId. Matches
        /// Invoke-CippTestCIS_1_1_2 / _1_1_3.
        /// </summary>
        public static HashSet<string> CollectGaUserIds(TenantData data, JsonElement ga)
        {
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var m in Arr(ga, "members"))
            {
                var mid = Str(m, "id");
                if (!string.IsNullOrEmpty(mid)) ids.Add(mid!);
            }

            var gaTemplate = Str(ga, "roleTemplateId");
            if (!string.IsNullOrEmpty(gaTemplate))
            {
                foreach (var a in Items(data.Get("RoleAssignmentScheduleInstances")))
                {
                    if (StrEq(a, "roleDefinitionId", gaTemplate!) && StrEq(a, "assignmentType", "Assigned")
                        && EndDateNull(a))
                    {
                        var pid = Str(a, "principalId");
                        if (!string.IsNullOrEmpty(pid)) ids.Add(pid!);
                    }
                }
            }
            return ids;
        }

        /// <summary>Users whose id is in <paramref name="ids"/> (ordinal, matching the PS HashSet.Contains).</summary>
        public static List<JsonElement> UsersByIds(TenantData data, HashSet<string> ids)
        {
            var list = new List<JsonElement>();
            foreach (var u in Items(data.Get("Users")))
            {
                var id = Str(u, "id");
                if (id != null && ids.Contains(id)) list.Add(u);
            }
            return list;
        }

        /// <summary>PS boolean string interpolation: True / False (used for `[bool]$x` cells).</summary>
        public static string BoolStr(bool v) => v ? "True" : "False";

        /// <summary>
        /// Case-insensitive multi-level property navigation. Each segment is a single property name
        /// (this splits on '.', so it must not be used for keys that themselves contain a dot —
        /// e.g. read <c>@odata.type</c> with a final single-level <see cref="Str"/> call). Returns a
        /// default (ValueKind.Undefined) element when any segment is missing or a non-object is hit.
        /// </summary>
        public static JsonElement PropPath(JsonElement el, string path)
        {
            var current = el;
            foreach (var segment in path.Split('.'))
            {
                if (current.ValueKind != JsonValueKind.Object) return default;
                if (!TryProp(current, segment, out current)) return default;
            }
            return current;
        }

        /// <summary>
        /// PowerShell <c>-contains</c> (case-insensitive) for a JSON array or a scalar string.
        /// An array matches when any element string-equals <paramref name="value"/>; a scalar string
        /// matches on equality; anything else (absent/null/number/object) does not match.
        /// </summary>
        public static bool ContainsCI(JsonElement collection, string value)
        {
            switch (collection.ValueKind)
            {
                case JsonValueKind.Array:
                    foreach (var e in collection.EnumerateArray())
                        if (e.ValueKind == JsonValueKind.String
                            && string.Equals(e.GetString(), value, StringComparison.OrdinalIgnoreCase))
                            return true;
                    return false;
                case JsonValueKind.String:
                    return string.Equals(collection.GetString(), value, StringComparison.OrdinalIgnoreCase);
                default:
                    return false;
            }
        }

        /// <summary>
        /// PowerShell <c>-match</c> (case-insensitive regex) over a JSON value that may be a scalar
        /// string or an array of strings (a match on any element). Absent/other kinds never match.
        /// </summary>
        public static bool MatchAny(JsonElement v, string pattern)
        {
            switch (v.ValueKind)
            {
                case JsonValueKind.String:
                    return Regex.IsMatch(v.GetString() ?? "", pattern, RegexOptions.IgnoreCase);
                case JsonValueKind.Array:
                    foreach (var e in v.EnumerateArray())
                        if (e.ValueKind == JsonValueKind.String
                            && Regex.IsMatch(e.GetString() ?? "", pattern, RegexOptions.IgnoreCase))
                            return true;
                    return false;
                default:
                    return false;
            }
        }

        /// <summary>Join a JSON array's string elements with ", " (PowerShell <c>-join ', '</c>). Non-strings render raw; empty/absent → "".</summary>
        public static string JoinCsv(JsonElement arr)
        {
            var parts = new List<string>();
            foreach (var e in Items(arr))
            {
                parts.Add(e.ValueKind switch
                {
                    JsonValueKind.String => e.GetString() ?? "",
                    JsonValueKind.Null or JsonValueKind.Undefined => "",
                    _ => e.GetRawText()
                });
            }
            return string.Join(", ", parts);
        }

        // ── leaf value access ───────────────────────────────────────────────────────────
        /// <summary>String value of an element itself (null for null/undefined; raw text otherwise).</summary>
        public static string? LeafStr(JsonElement v) => v.ValueKind switch
        {
            JsonValueKind.String => v.GetString(),
            JsonValueKind.Null or JsonValueKind.Undefined => null,
            _ => v.GetRawText()
        };

        /// <summary><c>&lt;element&gt; -eq 'value'</c> — case-insensitive string equality.</summary>
        public static bool LeafEqCI(JsonElement v, string value)
            => string.Equals(LeafStr(v), value, StringComparison.OrdinalIgnoreCase);

        /// <summary><c>&lt;element&gt; -eq $true</c> — real JSON true or the string "true"/"True".</summary>
        public static bool LeafIsTrue(JsonElement v)
            => v.ValueKind == JsonValueKind.True
               || (v.ValueKind == JsonValueKind.String
                   && string.Equals(v.GetString(), "true", StringComparison.OrdinalIgnoreCase));

        // ── array membership (all case-insensitive, matching PS -contains/-in) ────────────
        /// <summary><c>&lt;array&gt; -contains 'value'</c> — case-insensitive; false when not an array.</summary>
        public static bool ArrContainsCI(JsonElement arr, string value)
        {
            if (arr.ValueKind != JsonValueKind.Array) return false;
            foreach (var i in arr.EnumerateArray())
                if (i.ValueKind == JsonValueKind.String
                    && string.Equals(i.GetString(), value, StringComparison.OrdinalIgnoreCase))
                    return true;
            return false;
        }

        /// <summary><c>&lt;array&gt; -notcontains 'value'</c> (true when absent/not an array).</summary>
        public static bool ArrNotContainsCI(JsonElement arr, string value) => !ArrContainsCI(arr, value);

        /// <summary>Any string item of the array is in <paramref name="set"/> (using the set's own comparer).</summary>
        public static bool AnyStringInSet(JsonElement arr, ISet<string> set)
        {
            if (arr.ValueKind != JsonValueKind.Array) return false;
            foreach (var i in arr.EnumerateArray())
                if (i.ValueKind == JsonValueKind.String && i.GetString() is string s && set.Contains(s))
                    return true;
            return false;
        }

        /// <summary>Any non-null string item of the array satisfies <paramref name="pred"/> (PS Where-Object over a string list).</summary>
        public static bool AnyString(JsonElement arr, Func<string, bool> pred)
        {
            if (arr.ValueKind != JsonValueKind.Array) return false;
            foreach (var i in arr.EnumerateArray())
                if (i.ValueKind == JsonValueKind.String && i.GetString() is string s && pred(s))
                    return true;
            return false;
        }

        /// <summary>Join the string items of an array with <paramref name="sep"/> (PS <c>-join</c> over a string list).</summary>
        public static string JoinLeafStrings(JsonElement arr, string sep)
        {
            var list = new List<string>();
            if (arr.ValueKind == JsonValueKind.Array)
                foreach (var i in arr.EnumerateArray())
                    if (i.ValueKind == JsonValueKind.String) list.Add(i.GetString() ?? "");
                    else list.Add(LeafStr(i) ?? "");
            return string.Join(sep, list);
        }

        // ── numeric equality tolerant of EXO string serialisation ─────────────────────────
        /// <summary><c>$_.name -eq &lt;target&gt;</c> for a numeric field serialised as a number or a string.</summary>
        public static bool IntEq(JsonElement el, string name, long target)
        {
            if (!TryProp(el, name, out var v)) return false;
            return LeafIntEq(v, target);
        }

        /// <summary><c>&lt;element&gt; -eq &lt;target&gt;</c> for a numeric leaf (number or numeric string).</summary>
        public static bool LeafIntEq(JsonElement v, long target)
        {
            if (v.ValueKind == JsonValueKind.Number)
                return v.TryGetInt64(out var l) ? l == target : v.GetDouble() == target;
            if (v.ValueKind == JsonValueKind.String
                && long.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var sl))
                return sl == target;
            return false;
        }

        /// <summary><c>[int]$value</c> of a plain string, with PS's <c>$null</c>→0 coercion.</summary>
        public static long IntOfString(string? value)
            => long.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var l) ? l : 0;

        // ── array lookups ────────────────────────────────────────────────────────────────
        /// <summary>First item of the array element whose string property <paramref name="prop"/> equals <paramref name="value"/> (CI); null if none.</summary>
        public static JsonElement? FindInArray(JsonElement arr, string prop, string value)
        {
            if (arr.ValueKind != JsonValueKind.Array) return null;
            foreach (var i in arr.EnumerateArray())
                if (StrEq(i, prop, value)) return i;
            return null;
        }

        /// <summary>
        /// The privileged directory-role TEMPLATE ids (Reproduces <c>Get-CippDbRole -IncludePrivilegedRoles</c>
        /// followed by projecting each role's <c>roleTemplateId</c>). Empty when no privileged roles matched.
        /// </summary>
        public static HashSet<string> PrivRoleTemplateIdsFromData(TenantData data, StringComparer comparer)
        {
            var set = new HashSet<string>(comparer);
            foreach (var role in CippTestHelpers.GetPrivilegedRoles(data))
            {
                var tid = Str(role, "roleTemplateId");
                if (!string.IsNullOrEmpty(tid)) set.Add(tid!);
            }
            return set;
        }

        /// <summary>PS <c>[string]::IsNullOrEmpty($_.endDateTime)</c>: field absent, JSON null, or empty string.</summary>
        public static bool EndDateNullOrEmpty(JsonElement el)
        {
            if (!TryProp(el, "endDateTime", out var v)) return true;
            return v.ValueKind == JsonValueKind.Null
                   || (v.ValueKind == JsonValueKind.String && string.IsNullOrEmpty(v.GetString()));
        }

        // ── directory "Password Rule Settings" object (shared by CIS_5_2_3_2/3/8/9) ────────
        public const string PasswordRuleTemplateId = "5cf42378-d67d-4f36-ba46-e8b86229381d";

        /// <summary>
        /// First directory Settings record identified as "Password Rule Settings" (by templateId or
        /// displayName), or null. Mirrors the PS <c>Where-Object … | Select-Object -First 1</c>.
        /// </summary>
        public static JsonElement? FindPasswordRuleSetting(JsonElement settings)
        {
            foreach (var s in Items(settings))
                if (StrEq(s, "templateId", PasswordRuleTemplateId) || StrEq(s, "displayName", "Password Rule Settings"))
                    return s;
            return null;
        }

        /// <summary>
        /// Mirror PowerShell <c>@($_.name).Count</c>: an empty JSON array is 0, a populated array is
        /// its length, but <c>$null</c>/absent/scalar all wrap to a one-element array (Count 1) — the
        /// well-known <c>@($null).Count == 1</c> gotcha that CIS_6_1_2 relies on.
        /// </summary>
        public static int PsArrayCount(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return 1;          // $null → @($null).Count == 1
            return v.ValueKind == JsonValueKind.Array ? v.GetArrayLength() : 1;
        }

        /// <summary>
        /// Mirror PowerShell string interpolation <c>"$($_.name)"</c>: null/absent → "", an array →
        /// its items space-joined, a scalar → its rendered value.
        /// </summary>
        public static string PsStringify(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return "";
            if (v.ValueKind == JsonValueKind.Array)
            {
                var parts = new List<string>();
                foreach (var i in v.EnumerateArray()) parts.Add(Cell(i));
                return string.Join(" ", parts);
            }
            return Cell(v);
        }

        /// <summary>
        /// Reproduces the OWA default-policy selection several CIS 6.x tests share:
        /// <c>$Owa | Where-Object { $_.Identity -eq 'OwaMailboxPolicy-Default' -or $_.IsDefault -eq $true } | Select -First 1</c>,
        /// falling back to the first record. Null when the cache has no rows.
        /// </summary>
        public static JsonElement? PickOwaDefault(TenantData data)
        {
            JsonElement? first = null;
            foreach (var p in Items(data.Get("OwaMailboxPolicy")))
            {
                if (first == null) first = p;
                if (StrEq(p, "Identity", "OwaMailboxPolicy-Default") || CippTestHelpers.BoolEq(p, "IsDefault", true))
                    return p;
            }
            return first;
        }

        /// <summary>
        /// First record whose <c>Identity</c> equals <paramref name="identity"/> (case-insensitive),
        /// falling back to the first record. Null when the type has no rows. Mirrors
        /// <c>$X | Where-Object { $_.Identity -eq '&lt;identity&gt;' } | Select -First 1</c> with a first-record fallback.
        /// </summary>
        public static JsonElement? FirstByIdentityOrFirst(TenantData data, string type, string identity)
        {
            JsonElement? first = null;
            foreach (var p in Items(data.Get(type)))
            {
                if (first == null) first = p;
                if (StrEq(p, "Identity", identity)) return p;
            }
            return first;
        }

        /// <summary>
        /// Mirrors PowerShell <c>-not [string]::IsNullOrWhiteSpace($_.name)</c> for a value that may be
        /// a string OR a collection (the SharePoint domain lists are stored as either): a non-blank
        /// string, or a non-empty array, or any other non-null scalar counts as "present".
        /// </summary>
        public static bool HasNonBlankField(JsonElement el, string name)
        {
            if (!TryProp(el, name, out var v)) return false;
            return v.ValueKind switch
            {
                JsonValueKind.String => !string.IsNullOrWhiteSpace(v.GetString()),
                JsonValueKind.Array => v.GetArrayLength() > 0,
                JsonValueKind.Null or JsonValueKind.Undefined => false,
                _ => true,
            };
        }

        /// <summary>
        /// The set of recipient domains covered by a policy collection: the union of every policy's
        /// <c>RecipientDomainIs</c> values. RecipientDomainIs may be a scalar or an array (EXO returns
        /// either); <see cref="CippTestHelpers.StringValues"/> handles both. Case-insensitive, matching the
        /// PS <c>-notcontains</c> membership test.
        /// </summary>
        public static HashSet<string> CoveredRecipientDomains(JsonElement policies)
        {
            var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var policy in Items(policies))
                foreach (var domain in StringValues(policy, "RecipientDomainIs"))
                    set.Add(domain);
            return set;
        }

        /// <summary>
        /// The pass/fail result for a domain-coverage test, assuming both sources are present. Each
        /// accepted domain (by <c>DomainName</c>) must appear in the policies' covered-domain set.
        /// </summary>
        /// <param name="coveredByPhrase">e.g. "Safe Links policies" for the pass sentence.</param>
        /// <param name="totalPoliciesLabel">e.g. "Total Safe Links Policies" for the pass detail line.</param>
        /// <param name="missingPhrase">e.g. "a Safe Links policy" for the fail sentence.</param>
        public static CippTestResult DomainCoverageResult(
            JsonElement acceptedDomains, JsonElement policies,
            string coveredByPhrase, string totalPoliciesLabel, string missingPhrase)
        {
            var covered = CoveredRecipientDomains(policies);
            var without = new List<string>();
            foreach (var domain in Items(acceptedDomains))
            {
                var name = Str(domain, "DomainName");
                if (name == null || !covered.Contains(name))
                    without.Add(name ?? "");
            }

            int totalDomains = acceptedDomains.GetArrayLength();
            int totalPolicies = policies.GetArrayLength();

            if (without.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append($"All accepted domains are covered by {coveredByPhrase}.\n\n");
                sb.Append($"**Total Accepted Domains:** {totalDomains}\n");
                sb.Append($"**{totalPoliciesLabel}:** {totalPolicies}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{without.Count} domains do not have {missingPhrase}.\n\n");
            f.Append("**Domains Without Policy:**\n\n");
            foreach (var domain in without)
                f.Append($"- {domain}\n");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }

        // True when a PS `-not $Rule.<name>` would be false, i.e. the property is a non-empty array
        // or a non-empty scalar (an exclusion is present).
        private static bool HasAny(JsonElement rule, string name)
        {
            if (!TryProp(rule, name, out var v)) return false;
            return v.ValueKind switch
            {
                JsonValueKind.Array => v.GetArrayLength() > 0,
                JsonValueKind.Null or JsonValueKind.Undefined => false,
                JsonValueKind.String => !string.IsNullOrEmpty(v.GetString()),
                _ => true,
            };
        }

        // Domains covered by an enabled rule with a recipient-domain target and no recipient/group
        // exclusions, honoring per-domain ExceptIfRecipientDomainIs. (ORCA226/227.)
        private static HashSet<string> CoveredDomainsFromRules(JsonElement rules)
        {
            var covered = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var rule in Items(rules))
            {
                if (!StrEq(rule, "State", "Enabled")) continue;
                if (HasAny(rule, "ExceptIfSentTo") || HasAny(rule, "ExceptIfSentToMemberOf")) continue;
                var targets = StringValues(rule, "RecipientDomainIs").ToList();
                if (targets.Count == 0) continue;
                var excluded = new HashSet<string>(StringValues(rule, "ExceptIfRecipientDomainIs"), StringComparer.OrdinalIgnoreCase);
                foreach (var d in targets)
                    if (!excluded.Contains(d)) covered.Add(d);
            }
            return covered;
        }

        /// <summary>ORCA226/227: Pass when every accepted domain is covered by an enabled rule; else Fail.</summary>
        public static CippTestResult RuleCoverageResult(
            JsonElement acceptedDomains, JsonElement rules,
            string pluralLabel, string singularLabel, string totalRulesLabel)
        {
            var covered = CoveredDomainsFromRules(rules);
            var accepted = Items(acceptedDomains).ToList();
            var uncovered = new List<string>();
            foreach (var d in accepted)
            {
                var name = Str(d, "DomainName");
                if (!string.IsNullOrEmpty(name) && !covered.Contains(name!)) uncovered.Add(name!);
            }

            if (uncovered.Count == 0)
            {
                var sb = new StringBuilder($"All accepted domains are covered by {pluralLabel}.\n\n");
                sb.Append($"**Total Accepted Domains:** {accepted.Count}\n");
                sb.Append($"**{totalRulesLabel}:** {Items(rules).Count()}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var fb = new StringBuilder($"{uncovered.Count} domains are not fully covered by a {singularLabel}.\n\n");
            fb.Append("**Domains Without Full Policy Coverage:**\n\n");
            foreach (var d in uncovered) fb.Append($"- {d}\n");
            return new CippTestResult(TestStatus.Failed, fb.ToString());
        }

        /// <summary>ORCA230/231/232: Pass unless multiple enabled rules target the same domain (Informational).</summary>
        public static CippTestResult OverlapResult(JsonElement acceptedDomains, JsonElement rules, string label)
        {
            var ruleList = Items(rules).ToList();
            var overlaps = new List<(string Domain, List<JsonElement> Rules)>();

            foreach (var d in Items(acceptedDomains))
            {
                var name = Str(d, "DomainName");
                if (string.IsNullOrEmpty(name)) continue;
                var applicable = ruleList.Where(r =>
                    StrEq(r, "State", "Enabled") &&
                    StringValues(r, "RecipientDomainIs").Any(x => string.Equals(x, name, StringComparison.OrdinalIgnoreCase)) &&
                    !StringValues(r, "ExceptIfRecipientDomainIs").Any(x => string.Equals(x, name, StringComparison.OrdinalIgnoreCase))
                ).ToList();
                if (applicable.Count > 1) overlaps.Add((name!, applicable));
            }

            if (overlaps.Count == 0)
                return new CippTestResult(TestStatus.Passed, $"No overlapping {label} policy rules were found.");

            var sb = new StringBuilder($"Multiple {label} policy rules apply to one or more domains.\n\n");
            foreach (var (domain, rs) in overlaps)
            {
                sb.Append($"- **{domain}**\n");
                foreach (var r in rs.OrderBy(x => Int(x, "Priority")))
                {
                    sb.Append($"  - {Str(r, "Name")}");
                    if (TryProp(r, "Priority", out var pv) && pv.ValueKind != JsonValueKind.Null && pv.ValueKind != JsonValueKind.Undefined)
                        sb.Append($" (Priority: {Cell(pv)})");
                    sb.Append("\n");
                }
            }
            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }

        /// <summary>Case-insensitive string equality against a leaf element's string value.</summary>
        public static bool ValEq(JsonElement v, string value)
        {
            var s = v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Null or JsonValueKind.Undefined => null,
                _ => v.GetRawText()
            };
            return string.Equals(s, value, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>Assignment count (0 when absent/not an array), matching <c>$_.assignments.Count</c>.</summary>
        public static int AssignmentCount(JsonElement el)
            => TryProp(el, "assignments", out var a) && a.ValueKind == JsonValueKind.Array
                ? a.GetArrayLength() : 0;

        /// <summary>Case-insensitive substring test — mirrors PS <c>-match 'literal'</c> / <c>-like '*literal*'</c>.</summary>
        public static bool Contains(string? value, string sub)
            => value != null && value.IndexOf(sub, StringComparison.OrdinalIgnoreCase) >= 0;

        /// <summary>
        /// PowerShell member-access flattening over a graph. Walks <paramref name="path"/> from
        /// <paramref name="root"/>, flattening one level per step (so <c>settings.settingInstance
        /// .settingDefinitionId</c> over an array of settings yields every id), then expands any
        /// array leaves into their items. Yields leaf/child elements.
        /// </summary>
        public static IEnumerable<JsonElement> Chain(JsonElement root, params string[] path)
        {
            IEnumerable<JsonElement> cur = new[] { root };
            foreach (var name in path) cur = Step(cur, name);
            foreach (var e in cur)
            {
                if (e.ValueKind == JsonValueKind.Array)
                {
                    foreach (var i in e.EnumerateArray()) yield return i;
                }
                else if (e.ValueKind != JsonValueKind.Undefined && e.ValueKind != JsonValueKind.Null)
                {
                    yield return e;
                }
            }
        }

        private static IEnumerable<JsonElement> Step(IEnumerable<JsonElement> seq, string name)
        {
            foreach (var e in seq)
            {
                if (e.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in e.EnumerateArray())
                        if (TryProp(item, name, out var v)) yield return v;
                }
                else if (e.ValueKind == JsonValueKind.Object)
                {
                    if (TryProp(e, name, out var v)) yield return v;
                }
            }
        }

        /// <summary>
        /// Shared evaluation for the MFAState-based tests (SMB1001 2.5 / 2.6 / 2.9). Active members
        /// = AccountEnabled true and UserType != 'Guest'. A member is unprotected when the supplied
        /// CA-coverage predicate says so AND Security Defaults is not on AND per-user MFA is not
        /// Enforced/Enabled. The three tests differ only in the CA predicate and their prose.
        /// </summary>
        public static CippTestResult EvaluateMfaState(
            TenantData data,
            System.Func<string?, bool> caUnprotected,
            System.Func<int, string> passMessage,
            System.Func<int, int, string> failIntro)
        {
            var mfa = data.Get("MFAState");
            if (!Any(mfa))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "MFAState cache not found. Please refresh the cache for this tenant.");
            }

            var active = new List<JsonElement>();
            foreach (var u in Items(mfa))
                if (IsTrue(u, "AccountEnabled") && !StrEq(u, "UserType", "Guest")) active.Add(u);

            if (active.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "No active member accounts found.");
            }

            var unprotected = new List<JsonElement>();
            foreach (var u in active)
            {
                var perUser = Str(u, "PerUser");
                bool perUserOk = string.Equals(perUser, "Enforced", System.StringComparison.OrdinalIgnoreCase)
                              || string.Equals(perUser, "Enabled", System.StringComparison.OrdinalIgnoreCase);
                if (caUnprotected(Str(u, "CoveredByCA")) && !IsTrue(u, "CoveredBySD") && !perUserOk)
                    unprotected.Add(u);
            }

            if (unprotected.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, passMessage(active.Count));
            }

            var sb = new System.Text.StringBuilder();
            sb.Append(failIntro(unprotected.Count, active.Count));
            sb.Append("\n\n");
            var rows = new List<IReadOnlyList<string>>();
            foreach (var u in unprotected.Count > 25 ? unprotected.GetRange(0, 25) : unprotected)
            {
                rows.Add(new[]
                {
                    CellOf(u, "UPN"), CellOf(u, "CoveredByCA"), CellOf(u, "CoveredBySD"), CellOf(u, "PerUser")
                });
            }
            sb.Append(Markdown.Table(
                new[] { "User", "Covered by CA", "Security Defaults", "Per-user MFA" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
        }

        /// <summary>Render a JSON value as a string (null for null/undefined, raw text for non-strings).</summary>
        public static string? AsString(JsonElement v) => v.ValueKind switch
        {
            JsonValueKind.String => v.GetString(),
            JsonValueKind.Null or JsonValueKind.Undefined => null,
            _ => v.GetRawText()
        };

        /// <summary>Reproduces <c>$_.assignments -and $_.assignments.Count -gt 0</c>.</summary>
        public static bool IsAssigned(JsonElement record) => ArrayLen(record, "assignments") > 0;

        /// <summary>
        /// Reproduces the credential guard <c>$_.X -and $_.X.Count -gt 0 -and $_.X -ne '[]'</c>.
        /// The cache stores these as real JSON arrays (ConvertTo-Json -Depth 100), so the "[]" string
        /// case never fires; handled defensively anyway.
        /// </summary>
        public static bool HasCredentials(JsonElement record, string name)
        {
            if (!TryProp(record, name, out var v)) return false;
            if (v.ValueKind == JsonValueKind.Array) return v.GetArrayLength() > 0;
            if (v.ValueKind == JsonValueKind.String)
            {
                var s = v.GetString();
                return !string.IsNullOrEmpty(s) && s != "[]";
            }
            return false;
        }

        // ── nested single-object path ─────────────────────────────────────────────────
        /// <summary>Walk a chain of single-object properties, returning the leaf element (Undefined if broken).</summary>
        public static JsonElement Nested(JsonElement el, params string[] path)
        {
            var cur = el;
            foreach (var seg in path)
            {
                if (!TryProp(cur, seg, out cur)) return default;
            }
            return cur;
        }

        /// <summary>String value at the end of a single-object path (null if any hop is missing).</summary>
        public static string? NestedStr(JsonElement el, params string[] path)
        {
            var leaf = Nested(el, path);
            return leaf.ValueKind == JsonValueKind.Undefined ? null : AsString(leaf);
        }

        /// <summary>true iff the boolean at the end of a single-object path is JSON true / "true".</summary>
        public static bool NestedTrue(JsonElement el, params string[] path)
        {
            var leaf = Nested(el, path);
            return leaf.ValueKind == JsonValueKind.True
                || (leaf.ValueKind == JsonValueKind.String
                    && string.Equals(leaf.GetString(), "true", StringComparison.OrdinalIgnoreCase));
        }

        // ── member-enumeration flatten (PS $_.a.b.c over arrays) ──────────────────────
        /// <summary>
        /// Reproduce PowerShell chained member access over arrays: at each segment, project the named
        /// property from every current element, expanding array values into their items and dropping
        /// null/undefined. Starting from a single record, <c>Flatten(rec,"settings","settingInstance",
        /// "settingDefinitionId")</c> yields every setting-definition id, exactly like
        /// <c>$rec.settings.settingInstance.settingDefinitionId</c>.
        /// </summary>
        public static List<JsonElement> Flatten(JsonElement record, params string[] path)
        {
            var current = new List<JsonElement> { record };
            foreach (var seg in path)
            {
                var next = new List<JsonElement>(current.Count);
                foreach (var e in current)
                {
                    // Expand any array element itself before projecting (defensive).
                    if (e.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in e.EnumerateArray())
                            ProjectInto(item, seg, next);
                    }
                    else
                    {
                        ProjectInto(e, seg, next);
                    }
                }
                current = next;
            }
            // Final expand: if any leaf is itself an array, unroll it (PS enumerates the terminal array).
            var result = new List<JsonElement>(current.Count);
            foreach (var e in current)
            {
                if (e.ValueKind == JsonValueKind.Array)
                    foreach (var item in e.EnumerateArray())
                    {
                        if (item.ValueKind != JsonValueKind.Null && item.ValueKind != JsonValueKind.Undefined)
                            result.Add(item);
                    }
                else if (e.ValueKind != JsonValueKind.Null && e.ValueKind != JsonValueKind.Undefined)
                    result.Add(e);
            }
            return result;
        }

        private static void ProjectInto(JsonElement e, string seg, List<JsonElement> sink)
        {
            if (!TryProp(e, seg, out var v)) return;
            if (v.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in v.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.Null && item.ValueKind != JsonValueKind.Undefined)
                        sink.Add(item);
                }
            }
            else if (v.ValueKind != JsonValueKind.Null && v.ValueKind != JsonValueKind.Undefined)
            {
                sink.Add(v);
            }
        }

        /// <summary>Flatten a path and return the scalar string values (mirrors PS value list).</summary>
        public static List<string> FlattenStrings(JsonElement record, params string[] path)
        {
            var vals = Flatten(record, path);
            var result = new List<string>(vals.Count);
            foreach (var v in vals)
            {
                var s = AsString(v);
                if (s != null) result.Add(s);
            }
            return result;
        }

        /// <summary>true iff the flattened value list contains <paramref name="value"/> (CI) — PS <c>-contains</c>.</summary>
        public static bool FlattenContains(JsonElement record, string value, params string[] path)
            => FlattenStrings(record, path).Any(s => string.Equals(s, value, StringComparison.OrdinalIgnoreCase));

        // ── substring helpers (PS -like '*x*' / -match 'x') ──────────────────────────
        /// <summary>Case-insensitive substring test on a string-valued property (PS <c>-like '*x*'</c> / <c>-match 'x'</c>).</summary>
        public static bool PropContains(JsonElement el, string name, string substr)
        {
            var s = Str(el, name);
            return s != null && s.IndexOf(substr, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>Case-insensitive equality of a string-valued property to any of <paramref name="values"/> (PS <c>-in</c>).</summary>
        public static bool PropIn(JsonElement el, string name, params string[] values)
        {
            var s = Str(el, name);
            if (s == null) return false;
            foreach (var v in values)
                if (string.Equals(s, v, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>true iff the array-valued property contains the string <paramref name="value"/> (CI) — PS <c>-contains</c>.</summary>
        public static bool ArrContains(JsonElement el, string name, string value)
        {
            foreach (var i in Arr(el, name))
                if (string.Equals(AsString(i), value, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>The display value of a string-valued property, or "" when absent (for markdown).</summary>
        public static string Text(JsonElement el, string name) => Str(el, name) ?? "";

        /// <summary>
        /// Reproduces <c>Get-CippDbRoleMembers -RoleTemplateId</c>: merge three cached sources into one
        /// member list, de-duplicated by principal id (case-insensitive, as PS <c>-notcontains</c>):
        ///   Active   - RoleAssignmentScheduleInstances with assignmentType 'Assigned'
        ///   Eligible - RoleEligibilitySchedules (added when the id was not already seen)
        ///   Direct   - Roles.members for the template id (added when the id was not already seen)
        /// Active/Eligible members read their principal fields from the expanded <c>principal</c>
        /// object; Direct members read them off the member object itself.
        /// </summary>
        public static List<DbRoleMember> RoleMembers(TenantData data, string roleTemplateId)
        {
            var result = new List<DbRoleMember>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // Active: every 'Assigned' schedule instance for this role (no de-dup, matches PS).
            foreach (var a in Items(data.Get("RoleAssignmentScheduleInstances")))
            {
                if (!StrEq(a, "roleDefinitionId", roleTemplateId)) continue;
                if (!StrEq(a, "assignmentType", "Assigned")) continue;

                var principal = Prop(a, "principal");
                var end = Prop(a, "endDateTime");
                var m = new DbRoleMember
                {
                    Id = Str(a, "principalId"),
                    DisplayName = Str(principal, "displayName"),
                    UserPrincipalName = Str(principal, "userPrincipalName"),
                    AppId = Str(principal, "appId"),
                    ODataType = Str(principal, "@odata.type"),
                    AssignmentType = "Active",
                    IsPermanent = end.ValueKind == JsonValueKind.Null || end.ValueKind == JsonValueKind.Undefined
                };
                result.Add(m);
                if (m.Id != null) seen.Add(m.Id);
            }

            // Eligible: added only when the principal id has not already been seen.
            foreach (var e in Items(data.Get("RoleEligibilitySchedules")))
            {
                if (!StrEq(e, "roleDefinitionId", roleTemplateId)) continue;
                var pid = Str(e, "principalId");
                if (pid != null && seen.Contains(pid)) continue;

                var principal = Prop(e, "principal");
                var expirationType = NestedStr(e, "scheduleInfo", "expiration", "type");
                var m = new DbRoleMember
                {
                    Id = pid,
                    DisplayName = Str(principal, "displayName"),
                    UserPrincipalName = Str(principal, "userPrincipalName"),
                    AppId = Str(principal, "appId"),
                    ODataType = Str(principal, "@odata.type"),
                    AssignmentType = "Eligible",
                    IsPermanent = string.Equals(expirationType, "noExpiration", StringComparison.OrdinalIgnoreCase)
                };
                result.Add(m);
                if (pid != null) seen.Add(pid);
            }

            // Direct: directoryRole membership from the Roles cache, added when not already seen.
            foreach (var role in Items(data.Get("Roles")))
            {
                var tid = RoleTemplateId(role);
                if (tid == null || !string.Equals(tid, roleTemplateId, StringComparison.OrdinalIgnoreCase)) continue;

                foreach (var member in Arr(role, "members"))
                {
                    var mid = Str(member, "id");
                    if (mid != null && seen.Contains(mid)) continue;

                    var m = new DbRoleMember
                    {
                        Id = mid,
                        DisplayName = Str(member, "displayName"),
                        UserPrincipalName = Str(member, "userPrincipalName"),
                        AppId = Str(member, "appId"),
                        ODataType = Str(member, "@odata.type"),
                        AssignmentType = "Direct",
                        IsPermanent = true
                    };
                    result.Add(m);
                    if (mid != null) seen.Add(mid);
                }
            }

            return result;
        }

        /// <summary>
        /// Mirror <c>Get-Date $iso -Format 'yyyy-MM-dd'</c>: parse the ISO string and render the date,
        /// or "Never" when the value is null/absent. Cosmetic (dates are a known parity divergence).
        /// </summary>
        public static string SignInDate(string? iso)
        {
            if (string.IsNullOrEmpty(iso)) return "Never";
            if (DateTimeOffset.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dto))
                return dto.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            return iso!.Length >= 10 ? iso.Substring(0, 10) : iso;
        }

        /// <summary>
        /// Parse an ISO-ish datetime string to a <see cref="DateTimeOffset"/>, or null when it is
        /// empty/unparseable — mirrors a PS <c>[DateTime]</c> cast guarded by try/catch. Values are
        /// compared against <see cref="DateTimeOffset.Now"/> (PS <c>Get-Date</c> is local), so the
        /// instant is preserved regardless of the source offset.
        /// </summary>
        public static DateTimeOffset? ParseDate(string? s)
        {
            if (string.IsNullOrWhiteSpace(s)) return null;
            if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dt))
                return dt;
            return null;
        }

        /// <summary>Parse the string value of a property to a date (null when absent/unparseable).</summary>
        public static DateTimeOffset? ParseDateProp(JsonElement el, string name)
            => ParseDate(CippTestHelpers.Str(el, name));

        /// <summary>
        /// True when the leaf at the end of a single-object path exists and is not JSON null —
        /// mirrors PS <c>$null -ne $_.a.b.c</c>.
        /// </summary>
        public static bool NestedExists(JsonElement el, params string[] path)
        {
            var leaf = CippTestHelpers.Nested(el, path);
            return leaf.ValueKind != JsonValueKind.Undefined && leaf.ValueKind != JsonValueKind.Null;
        }

        /// <summary>Count of the flattened member-enumeration path (mirrors PS <c>$_.a.b.c.Count</c>).</summary>
        public static int FlattenCount(JsonElement el, params string[] path)
            => CippTestHelpers.Flatten(el, path).Count;

        /// <summary>
        /// Mirror PS <c>[DateTime]::Parse($s).ToString('yyyy-MM-dd HH:mm')</c>: parse to local time and
        /// format; on failure return the raw string verbatim (matching the PS try/catch fallback).
        /// </summary>
        public static string FormatDate(string s)
        {
            if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt))
                return dt.LocalDateTime.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
            return s;
        }

        /// <summary>Whole days between now and <paramref name="dt"/> as PS TimeSpan.Days (truncated).</summary>
        public static int WholeDaysSince(DateTimeOffset dt, DateTimeOffset now) => (now - dt).Days;

        /// <summary>Risk-level badge (PS switch): high/medium/low → emoji label, else the raw value.</summary>
        public static string RiskLevelBadge(string? level) => (level ?? "").ToLowerInvariant() switch
        {
            "high" => "🔴 High",
            "medium" => "🟡 Medium",
            "low" => "🟢 Low",
            _ => level ?? ""
        };

        /// <summary>Risk-state badge (PS switch): atRisk/confirmedCompromised/dismissed/remediated, else raw.</summary>
        public static string RiskStateBadge(string? state) => (state ?? "").ToLowerInvariant() switch
        {
            "atrisk" => "⚠️ At Risk",
            "confirmedcompromised" => "🔴 Confirmed Compromised",
            "dismissed" => "✅ Dismissed",
            "remediated" => "✅ Remediated",
            _ => state ?? ""
        };

    }

    /// <summary>One resolved directory-role member (active/eligible/direct), from RoleMembers.</summary>
    public sealed class DbRoleMember
    {
        public string? Id { get; set; }
        public string? DisplayName { get; set; }
        public string? UserPrincipalName { get; set; }
        public string? AppId { get; set; }
        public string? ODataType { get; set; }
        public string AssignmentType { get; set; } = "";
        public bool IsPermanent { get; set; }
        public bool IsUser => (ODataType ?? "").IndexOf("user", System.StringComparison.OrdinalIgnoreCase) >= 0;
        public bool IsServicePrincipal => (ODataType ?? "").IndexOf("servicePrincipal", System.StringComparison.OrdinalIgnoreCase) >= 0;
        public bool IsGroup => (ODataType ?? "").IndexOf("group", System.StringComparison.OrdinalIgnoreCase) >= 0;
    }

}