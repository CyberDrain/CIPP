using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.11.3 — Mailbox intelligence SHALL be enabled.
    /// Port of Invoke-CippTestCISAMSEXO113. Passes when at least one preset policy has both
    /// <c>EnableMailboxIntelligence</c> and <c>EnableMailboxIntelligenceProtection</c> enabled.
    /// </summary>
    public sealed class CISAMSEXO113 : ICippTest
    {
        public string Id => "CISAMSEXO113";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoPresetSecurityPolicy");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.");

            var withIntel = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (EqTrue(p, "EnableMailboxIntelligence") && EqTrue(p, "EnableMailboxIntelligenceProtection"))
                    withIntel.Add(p);
            }

            if (withIntel.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Fail**: No policies found with mailbox intelligence enabled.\n\n"
                    + "Enable mailbox intelligence in preset security policies for AI-powered impersonation protection.");

            var sb = new StringBuilder();
            sb.Append($"✅ **Pass**: {withIntel.Count} policy/policies have mailbox intelligence enabled:\n\n");
            sb.Append("| Policy | Mailbox Intelligence | Intelligence Protection | State |\n");
            sb.Append("| :----- | :------------------- | :---------------------- | :---- |\n");
            foreach (var p in withIntel)
                sb.Append($"| {Cell(p, "Identity")} | {Cell(p, "EnableMailboxIntelligence")} | {Cell(p, "EnableMailboxIntelligenceProtection")} | {Cell(p, "State")} |\n");
            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }
    }
}
