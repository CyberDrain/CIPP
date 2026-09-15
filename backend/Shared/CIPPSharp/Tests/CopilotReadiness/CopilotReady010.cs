using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All licensed users have MFA registered (security prerequisite for Copilot rollout).
    /// Port of Invoke-CippTestCopilotReady010. Joins UserRegistrationDetails + Users on UPN.
    /// NOTE: the PS source's second fail paragraph is single-quoted, so its trailing "`n`n" is
    /// four literal characters (backtick n backtick n), not two newlines — reproduced verbatim.
    /// </summary>
    public sealed class CopilotReady010 : ICippTest
    {
        public string Id => "CopilotReady010";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var registrationDetails = data.Get("UserRegistrationDetails");
            var allUsers = data.Get("Users");

            if (!Any(registrationDetails) || !Any(allUsers))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No MFA registration or user data found in database. Data collection may not yet have run for this tenant.");
            }

            var regLookup = LookupByUpn(registrationDetails);
            var licensedUsers = new List<JsonElement>();
            foreach (var user in Items(allUsers))
                if (IsLicensedAny(user)) licensedUsers.Add(user);

            if (licensedUsers.Count == 0)
                return new CippTestResult(TestStatus.Skipped, "No licensed active users found in the tenant.");

            var notRegistered = new List<string>();
            int registered = 0;
            foreach (var user in licensedUsers)
            {
                var upn = Str(user, "userPrincipalName") ?? "";
                if (regLookup.TryGetValue(upn.ToLowerInvariant(), out var reg) && IsTrue(reg, "isMfaRegistered"))
                    registered++;
                else
                    notRegistered.Add(upn);
            }

            int total = licensedUsers.Count;

            if (notRegistered.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All **{total} licensed users** have MFA registered — the tenant meets the MFA security baseline for Copilot deployment.");
            }

            double pct = Pct(notRegistered.Count, total);
            var f = new StringBuilder();
            f.Append($"**{notRegistered.Count} of {total} licensed users ({Fmt(pct)}%)** do not have MFA registered.\n\n");
            // Single-quoted in PS → the trailing backtick-n backtick-n is literal text, not newlines.
            f.Append("MFA is a security baseline requirement before deploying Copilot. Accounts without MFA present elevated risk when Copilot has access to tenant data.`n`n");
            f.Append("Remediate by enforcing MFA via Conditional Access or per-user MFA, and requiring users to register via [aka.ms/mfasetup](https://aka.ms/mfasetup).\n\n");
            if (notRegistered.Count <= 20)
            {
                f.Append("**Users without MFA registered:**\n");
                foreach (var upn in notRegistered) f.Append($"- {upn}\n");
            }
            else
            {
                f.Append($"**{notRegistered.Count} users** do not have MFA registered.");
            }
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
