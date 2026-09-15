using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.10.3 — Email scanning SHALL be capable of reviewing emails after delivery (ZAP).
    /// Port of Invoke-CippTestCISAMSEXO103. Fails policies where <c>-not ZapEnabled</c> (PS truthiness).
    /// </summary>
    public sealed class CISAMSEXO103 : ICippTest
    {
        public string Id => "CISAMSEXO103";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoMalwareFilterPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.");

            var failed = new List<JsonElement>();
            int total = 0;
            foreach (var p in Items(policies))
            {
                total++;
                if (NotTruthyProp(p, "ZapEnabled")) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} malware filter policy/policies have ZAP (Zero-hour Auto Purge) enabled.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} malware filter policy/policies do not have ZAP enabled:\n\n");
            sb.Append("| Policy Name | ZAP Enabled |\n");
            sb.Append("| :---------- | :---------- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "ZapEnabled")} |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
