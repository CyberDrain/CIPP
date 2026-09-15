using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Users are actively using OneDrive/SharePoint for file collaboration (Copilot value indicator).
    /// Port of Invoke-CippTestCopilotReady006. Joins CopilotReadinessActivity + Users on UPN.
    /// NOTE: the PS source string contains a backslash-u escape that PowerShell does NOT process,
    /// so it emits the literal 6 characters (backslash, u, 2, 0, 1, 4) — reproduced here as "\\u2014".
    /// </summary>
    public sealed class CopilotReady006 : ICippTest
    {
        private const int ActivityThresholdPercent = 50;

        public string Id => "CopilotReady006";

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
                if (lookup.TryGetValue(upn.ToLowerInvariant(), out var r) && IsTrue(r, "usesOfficeDocs"))
                    active++;
                else
                    inactive.Add(upn);
            }

            int total = licensedUsers.Count;
            double pct = Pct(active, total);

            if (pct >= ActivityThresholdPercent)
            {
                var sb = new StringBuilder();
                sb.Append($"**{active} of {total} licensed users ({Fmt(pct)}%)** worked on OneDrive or SharePoint files in the past 30 days \\u2014 above the {ActivityThresholdPercent}% threshold.\n\n");
                sb.Append("These users are strong candidates for Copilot, which provides the most value when users actively collaborate on files in Microsoft 365.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"Only **{active} of {total} licensed users ({Fmt(pct)}%)** worked on OneDrive or SharePoint files in the past 30 days \\u2014 below the {ActivityThresholdPercent}% threshold.\n\n");
            f.Append("Copilot delivers the most value when users regularly store and collaborate on files in OneDrive and SharePoint. ");
            f.Append("Consider driving file collaboration adoption before or alongside a Copilot rollout.\n\n");
            if (inactive.Count > 0 && inactive.Count <= 20)
            {
                f.Append("**Inactive users (no Office doc activity in 30 days):**\n");
                foreach (var upn in inactive) f.Append($"- {upn}\n");
            }
            else if (inactive.Count > 20)
            {
                f.Append($"**{inactive.Count} users** had no OneDrive or SharePoint file activity in the past 30 days.");
            }
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
