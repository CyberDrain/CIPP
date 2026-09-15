using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.4) — Safe Attachments policy SHALL be enabled.
    /// Port of Invoke-CippTestCIS_2_1_4. Passes when at least one policy is enabled with a
    /// blocking action.
    ///
    /// NOTE (parity limitation): as with CIS_2_1_1, the PS "collected but no policy" (→ Failed)
    /// vs "never collected" (→ Skipped) split relies on a count marker that TenantData cannot see;
    /// this port takes the Skipped branch on empty data.
    /// </summary>
    public sealed class CIS_2_1_4 : ICippTest
    {
        public string Id => "CIS_2_1_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoSafeAttachmentPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoSafeAttachmentPolicies has not been collected for this tenant. Run a Cache refresh (Cache & Tests); if it persists, the tenant may not have Defender for Office 365.");
            }

            var compliant = new List<JsonElement>();
            foreach (var p in policies.EnumerateArray())
            {
                if (IsTrue(p, "Enable") && InListCI(Str(p, "Action"), "Block", "Replace", "DynamicDelivery"))
                    compliant.Add(p);
            }

            if (compliant.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{compliant.Count} Safe Attachments policy/policies are enabled with a blocking action:\n\n");
                var lines = new List<string>();
                foreach (var p in compliant) lines.Add($"- {Str(p, "Name")} (Action: {Str(p, "Action")})");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Safe Attachments policy with a blocking action (Block/Replace/DynamicDelivery) was found.");
        }
    }
}
