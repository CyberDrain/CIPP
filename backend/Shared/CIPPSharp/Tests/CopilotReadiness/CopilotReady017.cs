using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Microsoft 365 Copilot active user count trend — is adoption growing or declining? (informational)
    /// Port of Invoke-CippTestCopilotReady017. Reflective: the count field is discovered from the
    /// first trend point via JsonElement.EnumerateObject().
    /// </summary>
    public sealed class CopilotReady017 : ICippTest
    {
        public string Id => "CopilotReady017";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var trendData = data.Get("CopilotUserCountTrend");
            if (!Any(trendData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Copilot user count trend data found in database. Data collection may not yet have run for this tenant.");
            }

            var trendPoints = Items(trendData)
                .Where(p => HasText(p, "reportDate"))
                .OrderBy(p => Str(p, "reportDate") ?? "", StringComparer.Ordinal)
                .ToList();

            if (trendPoints.Count == 0)
            {
                var msg = new StringBuilder();
                msg.Append("No Microsoft 365 Copilot usage trend data was found for the past 7 days.\n\n");
                msg.Append("This tenant either has no Copilot licenses assigned or users have not yet started using Copilot features.");
                return new CippTestResult(TestStatus.Informational, msg.ToString());
            }

            // First numeric-valued field whose name is not report/date/id.
            string? countField = null;
            foreach (var prop in trendPoints[0].EnumerateObject())
            {
                if (Regex.IsMatch(prop.Name, "report|date|id", RegexOptions.IgnoreCase)) continue;
                if (Regex.IsMatch(Cell(prop.Value), "^\\d+$")) { countField = prop.Name; break; }
            }

            var sb = new StringBuilder();
            sb.Append("## Copilot Active User Trend (Last 7 Days)\n\n");
            var rows = new List<IReadOnlyList<string>>();
            foreach (var point in trendPoints)
            {
                string count = countField != null ? Cell(Prop(point, countField)) : "N/A";
                rows.Add(new[] { Cell(Prop(point, "reportDate")), count });
            }
            sb.Append(Markdown.Table(new[] { "Date", "Active Users" }, rows));

            if (countField != null && trendPoints.Count >= 2)
            {
                int earliest = ParseInt(Cell(Prop(trendPoints[0], countField)));
                int latest = ParseInt(Cell(Prop(trendPoints[trendPoints.Count - 1], countField)));
                int delta = latest - earliest;

                string trendIcon, trendText;
                if (delta > 0)
                {
                    trendIcon = "📈";
                    trendText = $"**Trending up** — active Copilot users increased by {delta} over the 7-day window.";
                }
                else if (delta == 0)
                {
                    trendIcon = "➡️";
                    trendText = "**Stable** — active Copilot user count is unchanged over the 7-day window.";
                }
                else
                {
                    trendIcon = "📉";
                    trendText = $"**Trending down** — active Copilot users decreased by {Math.Abs(delta)} over the 7-day window. Consider reviewing adoption activities to re-engage users.";
                }
                sb.Append($"\n{trendIcon} {trendText}");
            }

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }

        private static int ParseInt(string s)
            => int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : 0;
    }
}
