using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Users are actively using Exchange Online email (Copilot value indicator).
    /// Port of Invoke-CippTestCopilotReady004. Joins CopilotReadinessActivity + Users on UPN.
    /// </summary>
    public sealed class CopilotReady004 : ICippTest
    {
        private const int ActivityThresholdPercent = 50;

        public string Id => "CopilotReady004";

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

            var inactive = new List<string>();
            int active = 0;
            foreach (var user in licensedUsers)
            {
                var upn = Str(user, "userPrincipalName") ?? "";
                if (lookup.TryGetValue(upn.ToLowerInvariant(), out var r) && IsTrue(r, "usesOutlookEmail"))
                    active++;
                else
                    inactive.Add(upn);
            }

            int total = licensedUsers.Count;
            double pct = Pct(active, total);

            if (pct >= ActivityThresholdPercent)
            {
                var sb = new StringBuilder();
                sb.Append($"**{active} of {total} licensed users ({Fmt(pct)}%)** sent email in the past 30 days — above the {ActivityThresholdPercent}% threshold.\n\n");
                sb.Append("These users are good candidates for Copilot in Outlook, which provides AI-assisted drafting, summarization, and email coaching.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"Only **{active} of {total} licensed users ({Fmt(pct)}%)** sent email in the past 30 days — below the {ActivityThresholdPercent}% threshold.\n\n");
            f.Append("Copilot for Outlook delivers the most value to active email users. ");
            f.Append("Consider reviewing Exchange Online license assignment and adoption before rolling out Copilot.\n\n");
            if (inactive.Count > 0 && inactive.Count <= 20)
            {
                f.Append("**Inactive users (no Outlook email in 30 days):**\n");
                foreach (var upn in inactive) f.Append($"- {upn}\n");
            }
            else if (inactive.Count > 20)
            {
                f.Append($"**{inactive.Count} users** had no Outlook email activity in the past 30 days.");
            }
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
