using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Per-user Microsoft 365 Copilot usage detail (informational, 30-day period).
    /// Port of Invoke-CippTestCopilotReady015. Reflective: app columns are discovered from the
    /// first active record via JsonElement.EnumerateObject().
    /// </summary>
    public sealed class CopilotReady015 : ICippTest
    {
        private static readonly HashSet<string> NonAppColumns = new(StringComparer.OrdinalIgnoreCase)
        { "userPrincipalName", "displayName", "lastActivityDate", "reportRefreshDate", "reportPeriod", "id" };

        public string Id => "CopilotReady015";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var usageData = data.Get("CopilotUsageUserDetail");
            if (!Any(usageData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Copilot usage data found in database. Data collection may not yet have run for this tenant.");
            }

            var active = new List<JsonElement>();
            foreach (var u in usageData.EnumerateArray())
                if (HasText(u, "userPrincipalName") && !StrEq(u, "userPrincipalName", "Not applicable"))
                    active.Add(u);

            if (active.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No Microsoft 365 Copilot usage was detected in the past 30 days.\n\nThis tenant either has no Copilot licenses assigned, or users have not yet started using Copilot features. See tests CopilotReady001 and CopilotReady002 to check licensing status.");
            }

            // Discover app columns from the first active record, preserving JSON order.
            var appColumns = new List<string>();
            foreach (var prop in active[0].EnumerateObject())
                if (!NonAppColumns.Contains(prop.Name)) appColumns.Add(prop.Name);

            var sb = new StringBuilder();
            sb.Append($"**{active.Count} users** had Copilot activity in the past 30 days.\n\n");

            var headers = new List<string> { "User", "Last Active" };
            headers.AddRange(appColumns);

            var display = active
                .OrderByDescending(u => Str(u, "lastActivityDate") ?? "", StringComparer.Ordinal)
                .Take(50)
                .ToList();

            var rows = new List<IReadOnlyList<string>>();
            foreach (var user in display)
            {
                var la = Str(user, "lastActivityDate");
                string lastActive = string.IsNullOrEmpty(la) ? "N/A" : la!;
                var cells = new List<string> { Str(user, "userPrincipalName") ?? "", lastActive };
                foreach (var col in appColumns) cells.Add(Cell(Prop(user, col)));
                rows.Add(cells);
            }

            sb.Append(Markdown.Table(headers, rows));

            if (active.Count > 50)
                sb.Append($"\n*Showing 50 of {active.Count} active users.*");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
