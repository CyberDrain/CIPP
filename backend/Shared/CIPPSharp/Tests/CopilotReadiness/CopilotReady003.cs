using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Users have Microsoft 365 desktop apps activated (Copilot prerequisite).
    /// Port of Invoke-CippTestCopilotReady003. Joins OfficeActivations + Users on UPN (lowercased).
    /// </summary>
    public sealed class CopilotReady003 : ICippTest
    {
        private const int DesktopThresholdPercent = 70;

        public string Id => "CopilotReady003";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var activationData = data.Get("OfficeActivations");
            var allUsers = data.Get("Users");

            if (Empty(activationData) && Empty(allUsers))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Office activation or user data found in database. Data collection may not yet have run for this tenant.");
            }

            var activationLookup = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var entry in Items(activationData))
            {
                var upn = Str(entry, "userPrincipalName");
                if (!string.IsNullOrEmpty(upn)) activationLookup[upn!.ToLowerInvariant()] = entry;
            }

            var licensedUsers = new List<JsonElement>();
            foreach (var user in Items(allUsers))
                if (IsOfficeLicensed(user)) licensedUsers.Add(user);

            if (licensedUsers.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No users with an active M365 Apps license were found. Desktop activation check is not applicable.");
            }

            var noDesktop = new List<(string display, string upn, long android, long ios, bool never)>();
            int desktopCount = 0;
            foreach (var user in licensedUsers)
            {
                var upn = Str(user, "userPrincipalName") ?? "";
                bool found = activationLookup.TryGetValue(upn.ToLowerInvariant(), out var activation);
                long win = 0, mac = 0, android = 0, ios = 0;
                if (found)
                {
                    win = SumOver(activation, "userActivationCounts", "windows");
                    mac = SumOver(activation, "userActivationCounts", "mac");
                    android = SumOver(activation, "userActivationCounts", "android");
                    ios = SumOver(activation, "userActivationCounts", "ios");
                }
                if (found && (win + mac) > 0)
                {
                    desktopCount++;
                }
                else
                {
                    noDesktop.Add((Str(user, "displayName") ?? "", upn, found ? android : 0, found ? ios : 0, !found));
                }
            }

            int totalUsers = licensedUsers.Count;
            double pct = Pct(desktopCount, totalUsers);

            if (pct >= DesktopThresholdPercent)
            {
                var sb = new StringBuilder();
                sb.Append($"**{desktopCount} of {totalUsers} licensed users ({Fmt(pct)}%)** have Microsoft 365 Apps activated on a desktop platform (Windows or Mac) — above the {DesktopThresholdPercent}% threshold.\n\n");
                sb.Append("These users can access Copilot features in desktop Word, Excel, PowerPoint, and Outlook.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"Only **{desktopCount} of {totalUsers} licensed users ({Fmt(pct)}%)** have Microsoft 365 Apps activated on a desktop platform — below the {DesktopThresholdPercent}% threshold.\n\n");
            f.Append("Copilot in Word, Excel, PowerPoint, and Outlook requires the M365 desktop application. ");
            f.Append("Users with only web or mobile activations, or who have never activated at all, cannot use Copilot's in-document features.\n\n");
            if (noDesktop.Count > 0 && noDesktop.Count <= 20)
            {
                f.Append("**Users without desktop activation:**\n");
                foreach (var u in noDesktop)
                {
                    string platformStr;
                    if (u.never)
                    {
                        platformStr = " (never activated)";
                    }
                    else
                    {
                        platformStr = (u.android > 0 || u.ios > 0) ? " (Mobile only)" : " (no activations)";
                    }
                    f.Append($"- {u.display} ({u.upn}){platformStr}\n");
                }
            }
            else if (noDesktop.Count > 20)
            {
                int neverActivated = noDesktop.FindAll(x => x.never).Count;
                f.Append($"**{noDesktop.Count} users** have no desktop M365 Apps activation");
                if (neverActivated > 0) f.Append($" ({neverActivated} have never activated on any platform)");
                f.Append(".\n");
            }
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }

        private static bool Empty(JsonElement arr) => arr.ValueKind != JsonValueKind.Array || arr.GetArrayLength() == 0;
    }
}
