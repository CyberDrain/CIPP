using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.11.2 — User warnings comparable to EOP safety tips SHOULD be displayed.
    /// Port of Invoke-CippTestCISAMSEXO112. Passes when at least one preset policy has any of the
    /// three impersonation safety tips enabled (OR across the three flags).
    /// </summary>
    public sealed class CISAMSEXO112 : ICippTest
    {
        public string Id => "CISAMSEXO112";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoPresetSecurityPolicy");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.");

            var withTips = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (EqTrue(p, "EnableSimilarUsersSafetyTips")
                    || EqTrue(p, "EnableSimilarDomainsSafetyTips")
                    || EqTrue(p, "EnableUnusualCharactersSafetyTips"))
                    withTips.Add(p);
            }

            if (withTips.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Fail**: No policies found with impersonation safety tips enabled.\n\n"
                    + "Enable safety tips in preset security policies to warn users about potential impersonation.");

            var sb = new StringBuilder();
            sb.Append($"✅ **Pass**: {withTips.Count} policy/policies have impersonation safety tips enabled:\n\n");
            sb.Append("| Policy | Similar Users Tips | Similar Domains Tips | Unusual Characters Tips |\n");
            sb.Append("| :----- | :----------------- | :------------------- | :---------------------- |\n");
            foreach (var p in withTips)
                sb.Append($"| {Cell(p, "Identity")} | {Cell(p, "EnableSimilarUsersSafetyTips")} | {Cell(p, "EnableSimilarDomainsSafetyTips")} | {Cell(p, "EnableUnusualCharactersSafetyTips")} |\n");
            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }
    }
}
