using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Copilot candidate tier breakdown — which users are most ready for Copilot (informational).
    /// Port of Invoke-CippTestCopilotReady008. Joins CopilotReadinessActivity + Users on UPN.
    /// </summary>
    public sealed class CopilotReady008 : ICippTest
    {
        public string Id => "CopilotReady008";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var readinessData = data.Get("CopilotReadinessActivity");
            var allUsers = data.Get("Users");

            if (!Any(readinessData) && !Any(allUsers))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Copilot readiness activity or user data found in database. Data collection may not yet have run for this tenant.");
            }

            var lookup = LookupByUpn(readinessData);
            var licensedUsers = new List<JsonElement>();
            foreach (var user in Items(allUsers))
                if (IsLicensedAny(user)) licensedUsers.Add(user);

            if (licensedUsers.Count == 0)
                return new CippTestResult(TestStatus.Skipped, "No licensed active users found in the tenant.");

            var high = new List<string>();
            var medium = new List<string>();
            var low = new List<string>();
            foreach (var user in licensedUsers)
            {
                var upn = Str(user, "userPrincipalName") ?? "";
                int score = lookup.TryGetValue(upn.ToLowerInvariant(), out var r) ? ReadinessScore(r) : 0;
                if (score >= 4) high.Add(upn);
                else if (score >= 3) medium.Add(upn);
                else low.Add(upn);
            }

            int total = licensedUsers.Count;
            string highPct = Fmt(Pct(high.Count, total));
            string medPct = Fmt(Pct(medium.Count, total));
            string lowPct = Fmt(Pct(low.Count, total));

            var sb = new StringBuilder();
            sb.Append("## Copilot Candidate Tier Breakdown\n\n");
            sb.Append("Scoring is based on 6 readiness signals from the Microsoft 365 Copilot Readiness report (30-day window).\n\n");
            var rows = new List<IReadOnlyList<string>>
            {
                new[] { "**High** (≥4 signals)", high.Count.ToString(), $"{highPct}%", "Power M365 users — strongest Copilot ROI" },
                new[] { "**Medium** (3 signals)", medium.Count.ToString(), $"{medPct}%", "Engaged users — good Copilot candidates" },
                new[] { "**Low** (≤2 signals)", low.Count.ToString(), $"{lowPct}%", "Low engagement — adopt M365 basics first" },
            };
            sb.Append(Markdown.Table(new[] { "Tier", "Users", "% of Tenant", "Description" }, rows));
            sb.Append("\n**Signals scored:** Copilot license assigned, qualified update channel, Teams meetings, Teams chat, Outlook email, Office documents (each = 1 point)\n");

            if (high.Count > 0 && high.Count <= 20)
            {
                sb.Append("\n**High tier users:**\n");
                foreach (var upn in high) sb.Append($"- {upn}\n");
            }
            else if (high.Count > 20)
            {
                sb.Append($"\n*{high.Count} users are in the high tier — use the Microsoft 365 Copilot Readiness report in the admin center for the full list.*\n");
            }

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
