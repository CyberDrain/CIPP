using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.15.1 — URL comparison with a block-list SHOULD be enabled.
    /// Port of Invoke-CippTestCISAMSEXO151. Fails Safe Links policies where
    /// <c>-not EnableSafeLinksForEmail</c> (PS truthiness).
    /// </summary>
    public sealed class CISAMSEXO151 : ICippTest
    {
        public string Id => "CISAMSEXO151";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoSafeLinksPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoSafeLinksPolicies cache not found. Please refresh the cache for this tenant.");

            var failed = new List<JsonElement>();
            int total = 0;
            foreach (var p in Items(policies))
            {
                total++;
                if (NotTruthyProp(p, "EnableSafeLinksForEmail")) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} Safe Links policy/policies have URL comparison with block-list enabled.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} Safe Links policy/policies do not have URL scanning enabled:\n\n");
            sb.Append("| Policy Name | Safe Links for Email |\n");
            sb.Append("| :---------- | :------------------- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "EnableSafeLinksForEmail")} |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
