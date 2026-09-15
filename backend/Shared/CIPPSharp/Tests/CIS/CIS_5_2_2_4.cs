using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.4) — Sign-in frequency SHALL be enabled and browser sessions not persistent
    /// for administrative users. Port of Invoke-CippTestCIS_5_2_2_4. Joins Conditional Access to the
    /// privileged directory roles (Get-CippDbRole -IncludePrivilegedRoles); CA includeRoles reference
    /// role TEMPLATE ids, so the PS builds a HashSet of roleTemplateId and does an ordinal Contains.
    /// </summary>
    public sealed class CIS_5_2_2_4 : ICippTest
    {
        public string Id => "CIS_5_2_2_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            var privRoleIds = PrivRoleTemplateIdsFromData(data, StringComparer.Ordinal);

            if (!Any(ca) || privRoleIds.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (ConditionalAccessPolicies or Roles) not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && PathTruthy(p, "conditions", "users", "includeRoles")
                    && AnyStringInSet(Path(p, "conditions", "users", "includeRoles"), privRoleIds)
                    && PathTruthy(p, "sessionControls")
                    && PathTruthy(p, "sessionControls", "signInFrequency")
                    && LeafIsTrue(Path(p, "sessionControls", "signInFrequency", "isEnabled"))
                    && PathTruthy(p, "sessionControls", "persistentBrowser")
                    && LeafEqCI(Path(p, "sessionControls", "persistentBrowser", "mode"), "never"))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies enforce admin sign-in frequency + non-persistent browser:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled CA policy enforces sign-in frequency AND non-persistent browser for privileged roles.");
        }
    }
}
