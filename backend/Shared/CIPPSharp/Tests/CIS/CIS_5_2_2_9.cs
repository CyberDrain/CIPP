using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.9) — A managed device SHALL be required for authentication.
    /// Port of Invoke-CippTestCIS_5_2_2_9. Any enabled CA policy requiring a compliant or
    /// hybrid/domain-joined device.
    /// </summary>
    public sealed class CIS_5_2_2_9 : ICippTest
    {
        public string Id => "CIS_5_2_2_9";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && PathTruthy(p, "grantControls")
                    && (ArrContainsCI(Path(p, "grantControls", "builtInControls"), "compliantDevice")
                        || ArrContainsCI(Path(p, "grantControls", "builtInControls"), "domainJoinedDevice")))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies require a compliant or domain-joined device:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy requires a compliant or hybrid-joined device.");
        }
    }
}
