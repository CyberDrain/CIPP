using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Microsoft 365 Copilot active user count summary by app (informational, 30-day period).
    /// Port of Invoke-CippTestCopilotReady016. Reflective: numeric app columns are discovered
    /// from the summary record via JsonElement.EnumerateObject().
    /// </summary>
    public sealed class CopilotReady016 : ICippTest
    {
        private static readonly HashSet<string> MetaFields = new(StringComparer.OrdinalIgnoreCase)
        { "reportRefreshDate", "reportPeriod", "reportDate", "id" };

        public string Id => "CopilotReady016";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var summaryData = data.Get("CopilotUserCountSummary");
            if (!Any(summaryData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Copilot user count summary data found in database. Data collection may not yet have run for this tenant.");
            }

            JsonElement summary = default;
            foreach (var el in summaryData.EnumerateArray()) { summary = el; break; }

            // Numeric (ValueType, non-bool) columns only, excluding metadata fields.
            var appCounts = new List<(string Name, JsonElement Value, double Num)>();
            foreach (var prop in summary.EnumerateObject())
            {
                if (MetaFields.Contains(prop.Name)) continue;
                if (prop.Value.ValueKind != JsonValueKind.Number) continue;
                appCounts.Add((prop.Name, prop.Value, prop.Value.GetDouble()));
            }

            double totalAppCount = appCounts.Sum(a => a.Num);
            if (appCounts.Count == 0 || totalAppCount == 0)
            {
                var msg = new StringBuilder();
                msg.Append("No Microsoft 365 Copilot usage was detected in the past 30 days.\n\n");
                msg.Append("This tenant either has no Copilot licenses assigned or users have not yet started using Copilot features.");
                return new CippTestResult(TestStatus.Informational, msg.ToString());
            }

            var sb = new StringBuilder();
            sb.Append("## Copilot Active Users by App (Last 30 Days)\n\n");
            var rows = new List<IReadOnlyList<string>>();
            foreach (var app in appCounts.OrderByDescending(a => a.Num))
            {
                // Insert a space before an interior capital, then drop the words "Active Users".
                string appName = Regex.Replace(app.Name, "([a-z])([A-Z])", "$1 $2");
                appName = Regex.Replace(appName, "Active Users", "", RegexOptions.IgnoreCase);
                rows.Add(new[] { appName.Trim(), Cell(app.Value) });
            }
            sb.Append(Markdown.Table(new[] { "App", "Active Users" }, rows));

            var refresh = Str(summary, "reportRefreshDate");
            if (!string.IsNullOrEmpty(refresh))
                sb.Append($"\n*Data as of {refresh}.*");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
