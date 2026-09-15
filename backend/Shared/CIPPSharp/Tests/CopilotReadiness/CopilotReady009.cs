using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Majority of licensed users are Medium or High Copilot candidates (adoption readiness).
    /// Port of Invoke-CippTestCopilotReady009. Same 6-signal scoring as test 008; pass at >=70%.
    /// </summary>
    public sealed class CopilotReady009 : ICippTest
    {
        private const int AdoptionThresholdPercent = 70;

        public string Id => "CopilotReady009";

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

            int mediumOrAbove = 0, lowCount = 0;
            foreach (var user in licensedUsers)
            {
                var upn = Str(user, "userPrincipalName") ?? "";
                int score = lookup.TryGetValue(upn.ToLowerInvariant(), out var r) ? ReadinessScore(r) : 0;
                if (score >= 3) mediumOrAbove++; else lowCount++;
            }

            int total = licensedUsers.Count;
            double pct = Pct(mediumOrAbove, total);

            if (pct >= AdoptionThresholdPercent)
            {
                var sb = new StringBuilder();
                sb.Append($"**{mediumOrAbove} of {total} licensed users ({Fmt(pct)}%)** score Medium or above on Copilot readiness signals — above the {AdoptionThresholdPercent}% threshold.\n\n");
                sb.Append("This tenant has strong M365 engagement across the user base and is well-positioned for a Copilot rollout.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"Only **{mediumOrAbove} of {total} licensed users ({Fmt(pct)}%)** score Medium or above on Copilot readiness signals — below the {AdoptionThresholdPercent}% threshold.\n\n");
            f.Append($"**{lowCount} users** have low M365 engagement (≤2 of 6 signals). Copilot delivers the most value where users are already active across Teams, Outlook, and Office apps.\n\n");
            f.Append("Consider running an M365 adoption campaign — focused on Teams meetings, Teams chat, Outlook, and OneDrive/SharePoint file usage — before or alongside a Copilot rollout.\n\n");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
