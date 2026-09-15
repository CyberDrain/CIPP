using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.5) — 'Phishing-resistant MFA strength' SHALL be required for Administrators.
    /// Port of Invoke-CippTestCIS_5_2_2_5. Joins Conditional Access to the privileged roles; the PS
    /// uses <c>-in</c> (case-insensitive) for the includeRoles membership check.
    /// </summary>
    public sealed class CIS_5_2_2_5 : ICippTest
    {
        public string Id => "CIS_5_2_2_5";

        private const string PhishResistantId = "00000000-0000-0000-0000-000000000004";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            var privRoleIds = PrivRoleTemplateIdsFromData(data, StringComparer.OrdinalIgnoreCase);

            if (!Any(ca) || privRoleIds.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (ConditionalAccessPolicies or Roles) not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && PathTruthy(p, "conditions", "users", "includeRoles")
                    && AnyStringInSet(Path(p, "conditions", "users", "includeRoles"), privRoleIds)
                    && PathTruthy(p, "grantControls", "authenticationStrength")
                    && LeafEqCI(Path(p, "grantControls", "authenticationStrength", "id"), PhishResistantId))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies require phishing-resistant MFA for privileged roles:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy enforces phishing-resistant MFA strength for privileged roles.");
        }
    }
}
