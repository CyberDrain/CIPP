using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.15.2 — Real-time suspicious URL and file-link scanning SHOULD be enabled.
    /// Port of Invoke-CippTestCISAMSEXO152. Fails Safe Links policies where <c>-not ScanUrls</c>.
    /// </summary>
    public sealed class CISAMSEXO152 : ICippTest
    {
        public string Id => "CISAMSEXO152";

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
                if (NotTruthyProp(p, "ScanUrls")) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} Safe Links policy/policies have real-time URL scanning enabled.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} Safe Links policy/policies do not have real-time URL scanning enabled:\n\n");
            sb.Append("| Policy Name | Scan URLs |\n");
            sb.Append("| :---------- | :-------- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "ScanUrls")} |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
