using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Privileged users have short-lived sign-in sessions.
    /// Port of Invoke-CippTestZTNA21825. Every privileged role must be covered by an enabled CA policy
    /// (targeting the role by id) that enforces a sign-in frequency of ≤4 hours.
    /// </summary>
    public sealed class ZTNA21825 : ICippTest
    {
        private const int RecommendedMaxHours = 4;

        public string Id => "ZTNA21825";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            if (privilegedRoles.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var caPolicies = new List<JsonElement>();
            foreach (var p in Items(data.Get("ConditionalAccessPolicies"))) caPolicies.Add(p);

            int roleScoped = 0;
            foreach (var p in caPolicies)
                if (ArrayLen(Nested(p, "conditions", "users"), "includeRoles") > 0) roleScoped++;

            var md = new StringBuilder("## Privileged User Sign-In Sessions\n\n");
            md.Append($"**Total Privileged Roles Found:** {privilegedRoles.Count}\n\n");
            md.Append($"**CA Policies Targeting Roles:** {roleScoped}\n\n");
            md.Append($"**Recommended Sign In Session Hours:** {RecommendedMaxHours}\n\n");
            md.Append("### Conditional Access Policies by Privileged Role\n\n");

            bool allRolesCovered = true;

            foreach (var role in privilegedRoles)
            {
                var roleId = Str(role, "id");
                md.Append($"#### {Text(role, "displayName")}\n\n");

                var enabled = new List<JsonElement>();
                foreach (var p in caPolicies)
                    if (roleId != null && FlattenContains(p, roleId, "conditions", "users", "includeRoles") && StrEq(p, "state", "enabled"))
                        enabled.Add(p);

                if (enabled.Count > 0)
                {
                    int compliantForRole = 0;
                    foreach (var p in enabled)
                    {
                        var sif = Nested(p, "sessionControls", "signInFrequency");
                        if (sif.ValueKind != JsonValueKind.Undefined && sif.ValueKind != JsonValueKind.Null
                            && StrEq(sif, "type", "hours") && TryDouble(Prop(sif, "value"), out var v) && v <= RecommendedMaxHours)
                            compliantForRole++;
                    }

                    string roleStatus;
                    if (compliantForRole > 0) roleStatus = "✅ Covered";
                    else { roleStatus = "❌ Not Covered"; allRolesCovered = false; }
                    md.Append($"**Status:** {roleStatus}\n\n");

                    md.Append("| Policy Name | Sign-In Frequency | Compliant |\n");
                    md.Append("| :--- | :--- | :--- |\n");
                    foreach (var p in enabled)
                    {
                        var sif = Nested(p, "sessionControls", "signInFrequency");
                        string freqValue = "Not Configured";
                        string isCompliant = "❌";
                        if (sif.ValueKind != JsonValueKind.Undefined && sif.ValueKind != JsonValueKind.Null)
                        {
                            var type = Str(sif, "type");
                            freqValue = $"{Cell(Prop(sif, "value"))} {type}";
                            if (string.Equals(type, "hours", StringComparison.OrdinalIgnoreCase) && TryDouble(Prop(sif, "value"), out var v))
                            {
                                if (v <= RecommendedMaxHours) isCompliant = "✅";
                                else isCompliant = $"⚠️ ({Cell(Prop(sif, "value"))}h > {RecommendedMaxHours}h)";
                            }
                            else isCompliant = "❌ (Days not recommended)";
                        }
                        var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/{Str(p, "id")}";
                        md.Append($"| [{Text(p, "displayName")}]({link}) | {freqValue} | {isCompliant} |\n");
                    }
                    md.Append("\n");
                }
                else
                {
                    md.Append("**Status:** ❌ No CA policies assigned\n\n");
                    md.Append("*No Conditional Access policies target this privileged role.*\n\n");
                    allRolesCovered = false;
                }
            }

            bool passed = allRolesCovered && privilegedRoles.Count > 0;
            if (passed)
                md.Append($"✅ **All privileged roles are covered by enabled policies enforcing short-lived sessions (≤{RecommendedMaxHours} hours).**\n");
            else
            {
                md.Append("❌ **Not all privileged roles are covered by compliant sign-in frequency controls.**\n");
                md.Append($"\n**Recommendation:** Configure Conditional Access policies to enforce sign-in frequency of {RecommendedMaxHours} hours or less for ALL privileged roles.\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, md.ToString());
        }

        private static bool TryDouble(JsonElement v, out double d)
        {
            d = 0;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out d)) return true;
            if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out d)) return true;
            return false;
        }
    }
}
