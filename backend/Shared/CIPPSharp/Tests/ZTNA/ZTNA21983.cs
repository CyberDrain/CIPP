using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// No Active Medium priority Entra recommendations found.
    /// Port of Invoke-CippTestZTNA21983. Skipped on no DirectoryRecommendations data; Passed when no
    /// recommendation has status 'active' and priority 'medium'.
    /// </summary>
    public sealed class ZTNA21983 : ICippTest
    {
        public string Id => "ZTNA21983";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var recs = data.Get("DirectoryRecommendations");
            if (!Any(recs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var active = new List<JsonElement>();
            foreach (var r in Items(recs))
                if (StrEq(r, "status", "active") && StrEq(r, "priority", "medium")) active.Add(r);

            if (active.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No active medium-priority Microsoft Entra recommendations were found.");

            var lines = new List<string>
            {
                $"{active.Count} active medium-priority Microsoft Entra recommendation(s) found.",
                "",
                "| Recommendation | Impact | Last Action |",
                "| :------------- | :----- | :---------- |"
            };

            for (int i = 0; i < active.Count && i < 25; i++)
            {
                var r = active[i];
                lines.Add($"| {Text(r, "displayName")} | {Str(r, "impactType") ?? "-"} | {Str(r, "lastModifiedDateTime") ?? "-"} |");
            }

            if (active.Count > 25)
            {
                lines.Add("");
                lines.Add($"...and {active.Count - 25} more.");
            }

            lines.Add("");
            lines.Add("**Remediation:** Review the recommendations in the Microsoft Entra admin center under Identity > Overview > Recommendations and apply or postpone each item.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
