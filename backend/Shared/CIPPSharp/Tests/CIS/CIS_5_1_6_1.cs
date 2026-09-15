using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.6.1) — Collaboration invitations SHALL be sent to allowed domains only. Port of
    /// Invoke-CippTestCIS_5_1_6_1. Sources: CrossTenantAccessPolicy + B2BManagementPolicy. The B2B
    /// policy inherits from stsPolicy, so its settings live in <c>definition[0]</c> as a JSON string.
    /// </summary>
    public sealed class CIS_5_1_6_1 : ICippTest
    {
        public string Id => "CIS_5_1_6_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var cross = data.Get("CrossTenantAccessPolicy");
            var b2b = data.Get("B2BManagementPolicy");

            if (!Any(cross) && !Any(b2b))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (CrossTenantAccessPolicy or B2BManagementPolicy) not found. Please refresh the cache for this tenant.");
            }

            // $B2B | where isOrganizationDefault -eq $true | first; else first.
            JsonElement? cfg = null;
            foreach (var p in Items(b2b))
            {
                if (IsTrue(p, "isOrganizationDefault")) { cfg = p; break; }
            }
            if (cfg == null) cfg = FirstOrNull(b2b);

            if (cfg == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No B2B management policy with domain restrictions was found.");
            }

            // @($Cfg.definition)[0] | ConvertFrom-Json → .B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy
            var allowed = new List<string>();
            var blocked = new List<string>();

            var def = PropPath(cfg.Value, "definition");
            string? defStr = null;
            if (def.ValueKind == JsonValueKind.Array)
            {
                var f = FirstOrNull(def);
                if (f != null && f.Value.ValueKind == JsonValueKind.String) defStr = f.Value.GetString();
            }
            else if (def.ValueKind == JsonValueKind.String)
            {
                defStr = def.GetString();
            }

            if (!string.IsNullOrEmpty(defStr))
            {
                try
                {
                    using var doc = JsonDocument.Parse(defStr!);
                    var inv = PropPath(PropPath(doc.RootElement, "B2BManagementPolicy"),
                        "InvitationsAllowedAndBlockedDomainsPolicy");
                    foreach (var d in Arr(inv, "AllowedDomains")) if (d.ValueKind == JsonValueKind.String) allowed.Add(d.GetString() ?? "");
                    foreach (var d in Arr(inv, "BlockedDomains")) if (d.ValueKind == JsonValueKind.String) blocked.Add(d.GetString() ?? "");
                }
                catch
                {
                    // PS uses -ErrorAction SilentlyContinue: a bad definition leaves both lists empty → Failed.
                }
            }

            if (allowed.Count > 0 || blocked.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"B2B invitations are scoped by an allow/block list (allowed: {string.Join(", ", allowed)}; blocked: {string.Join(", ", blocked)}).");
            }

            return new CippTestResult(TestStatus.Failed,
                "B2B invitations are not constrained by an allow / block list. Configure invitationsAllowedAndBlockedDomainsPolicy.");
        }
    }
}
