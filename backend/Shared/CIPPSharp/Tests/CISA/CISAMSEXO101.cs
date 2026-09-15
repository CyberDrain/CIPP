using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.10.1 — Emails SHALL be filtered by attachment file types.
    /// Port of Invoke-CippTestCISAMSEXO101. Fails malware filter policies where
    /// <c>-not EnableFileFilter</c> (PS truthiness — see <see cref="CippTestHelpers.Truthy"/>).
    /// </summary>
    public sealed class CISAMSEXO101 : ICippTest
    {
        public string Id => "CISAMSEXO101";

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
                if (NotTruthyProp(p, "EnableFileFilter")) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} malware filter policy/policies have file filtering enabled.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} malware filter policy/policies do not have file filtering enabled:\n\n");
            sb.Append("| Policy Name | File Filter Enabled |\n");
            sb.Append("| :---------- | :------------------ |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "EnableFileFilter")} |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
