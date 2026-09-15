using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Address high priority Entra recommendations.
    /// Port of Invoke-CippTestZTNA22124. Skipped on no DirectoryRecommendations data; Passed when no
    /// high-priority recommendation is active or postponed.
    /// </summary>
    public sealed class ZTNA22124 : ICippTest
    {
        public string Id => "ZTNA22124";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var recs = data.Get("DirectoryRecommendations");
            if (!Any(recs))
                return new CippTestResult(TestStatus.Skipped, "Unable to retrieve directory recommendations from cache.");

            var issues = new List<JsonElement>();
            foreach (var r in Items(recs))
                if (StrEq(r, "priority", "high") && PropIn(r, "status", "active", "postponed")) issues.Add(r);

            if (issues.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: All high priority Entra recommendations have been addressed.\n\n"
                    + "[View recommendations](https://entra.microsoft.com/#view/Microsoft_Azure_SecureScore/OverviewBlade)");

            var sb = new StringBuilder($"❌ **Fail**: There are {issues.Count} high priority recommendation(s) that have not been addressed.\n\n");
            sb.Append("## Outstanding high priority recommendations\n\n");
            sb.Append("| Display Name | Status | Insights |\n");
            sb.Append("| :----------- | :----- | :------- |\n");
            foreach (var r in issues)
            {
                var display = string.IsNullOrEmpty(Str(r, "displayName")) ? "N/A" : Str(r, "displayName");
                var status = string.IsNullOrEmpty(Str(r, "status")) ? "N/A" : Str(r, "status");
                var insights = string.IsNullOrEmpty(Str(r, "insights")) ? "N/A" : Str(r, "insights");
                sb.Append($"| {display} | {status} | {insights} |\n");
            }
            sb.Append("\n[Address recommendations](https://entra.microsoft.com/#view/Microsoft_Azure_SecureScore/OverviewBlade)");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
