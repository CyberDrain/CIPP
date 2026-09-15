using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Users are on a qualified Microsoft 365 Apps update channel (Copilot prerequisite).
    /// Port of Invoke-CippTestCopilotReady007. Joins CopilotReadinessActivity + Users (office-licensed) on UPN.
    /// </summary>
    public sealed class CopilotReady007 : ICippTest
    {
        private const int ChannelThresholdPercent = 70;

        public string Id => "CopilotReady007";

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
                if (IsOfficeLicensed(user)) licensedUsers.Add(user);

            if (licensedUsers.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No users with an active M365 Apps license were found. Update channel check is not applicable.");
            }

            var notQualified = new List<string>();
            int qualified = 0;
            foreach (var user in licensedUsers)
            {
                var upn = Str(user, "userPrincipalName") ?? "";
                if (lookup.TryGetValue(upn.ToLowerInvariant(), out var r) && IsTrue(r, "onQualifiedUpdateChannel"))
                    qualified++;
                else
                    notQualified.Add(upn);
            }

            int total = licensedUsers.Count;
            double pct = Pct(qualified, total);

            if (pct >= ChannelThresholdPercent)
            {
                var sb = new StringBuilder();
                sb.Append($"**{qualified} of {total} M365 Apps licensed users ({Fmt(pct)}%)** are on Current Channel or Monthly Enterprise Channel — above the {ChannelThresholdPercent}% threshold.\n\n");
                sb.Append("These users will receive Copilot feature updates for desktop Word, Excel, PowerPoint, Outlook, and OneNote.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"Only **{qualified} of {total} M365 Apps licensed users ({Fmt(pct)}%)** are on a qualified update channel — below the {ChannelThresholdPercent}% threshold.\n\n");
            f.Append("Copilot in M365 desktop apps requires **Current Channel** or **Monthly Enterprise Channel**. ");
            f.Append("Users on Semi-Annual Enterprise Channel or other update rings will not receive Copilot features.\n\n");
            f.Append("To remediate, update the Microsoft 365 Apps update channel via Microsoft Intune, Microsoft 365 admin center, or Group Policy.\n\n");
            if (notQualified.Count > 0 && notQualified.Count <= 20)
            {
                f.Append("**Users not on a qualified update channel:**\n");
                foreach (var upn in notQualified) f.Append($"- {upn}\n");
            }
            else if (notQualified.Count > 20)
            {
                f.Append($"**{notQualified.Count} users** are not on a qualified update channel.");
            }
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
