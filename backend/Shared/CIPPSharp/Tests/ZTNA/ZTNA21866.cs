using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All Microsoft Entra recommendations are addressed.
    /// Port of Invoke-CippTestZTNA21866. Skipped on no DirectoryRecommendations data; Passed when no
    /// recommendation is in status 'active' or 'postponed'.
    /// </summary>
    public sealed class ZTNA21866 : ICippTest
    {
        public string Id => "ZTNA21866";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var recs = data.Get("DirectoryRecommendations");
            if (!Any(recs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var unaddressed = new List<JsonElement>();
            foreach (var r in Items(recs))
                if (PropIn(r, "status", "active", "postponed")) unaddressed.Add(r);

            if (unaddressed.Count == 0)
                return new CippTestResult(TestStatus.Passed, "✅ All Entra Recommendations are addressed.");

            var sb = new StringBuilder($"❌ Found {unaddressed.Count} unaddressed Entra recommendations.\n\n");
            sb.Append("## Unaddressed Entra recommendations\n\n");
            sb.Append("| Display Name | Status | Insights | Priority |\n");
            sb.Append("| :--- | :--- | :--- | :--- |\n");
            foreach (var r in unaddressed)
                sb.Append($"| {Text(r, "displayName")} | {Text(r, "status")} | {Text(r, "insights")} | {Text(r, "priority")} |\n");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
