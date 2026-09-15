using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Inactive guest identities are disabled or removed from the tenant.
    /// Port of Invoke-CippTestZTNA21858. Enabled guests whose last successful sign-in (or, if never,
    /// creation date) is more than 90 days ago are flagged. Skipped on no Guests data; Passed when
    /// there are no enabled guests or none are inactive.
    /// </summary>
    public sealed class ZTNA21858 : ICippTest
    {
        public string Id => "ZTNA21858";
        private const int InactivityThresholdDays = 90;

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var guests = data.Get("Guests");
            if (!Any(guests))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var now = DateTimeOffset.Now;

            var enabled = new List<JsonElement>();
            foreach (var g in Items(guests))
                if (IsTrue(g, "accountEnabled")) enabled.Add(g);

            if (enabled.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No guest users found in the tenant");

            // Each inactive guest keeps its reference date (sign-in if present, else created).
            var inactive = new List<(JsonElement Guest, DateTimeOffset RefDate, bool HasSignIn)>();
            foreach (var g in enabled)
            {
                var signIn = ParseDate(NestedStr(g, "signInActivity", "lastSuccessfulSignInDateTime"));
                var created = ParseDateProp(g, "createdDateTime");

                DateTimeOffset? refDate = signIn ?? created;
                if (refDate is null) continue;

                if (WholeDaysSince(refDate.Value, now) > InactivityThresholdDays)
                    inactive.Add((g, refDate.Value, signIn.HasValue));
            }

            if (inactive.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All enabled guest users have been active within the last {InactivityThresholdDays} days");

            var lines = new List<string>
            {
                $"Found {inactive.Count} inactive guest user(s) with no sign-in activity in the last {InactivityThresholdDays} days.",
                "",
                $"**Total enabled guests:** {enabled.Count}",
                $"**Inactive guests:** {inactive.Count}",
                $"**Inactivity threshold:** {InactivityThresholdDays} days",
                "",
                "**Top 10 inactive guest users:**"
            };

            foreach (var entry in inactive.OrderBy(e => e.RefDate).Take(10))
            {
                var g = entry.Guest;
                var name = Text(g, "displayName");
                var upn = Text(g, "userPrincipalName");
                var days = Round0((now - entry.RefDate).TotalDays).ToString("0", CultureInfo.InvariantCulture);
                lines.Add(entry.HasSignIn
                    ? $"- {name} ({upn}) - Last sign-in: {days} days ago"
                    : $"- {name} ({upn}) - Never signed in (Created {days} days ago)");
            }

            if (inactive.Count > 10)
                lines.Add($"- ... and {inactive.Count - 10} more inactive guest(s)");

            lines.Add("");
            lines.Add("**Recommendation:** Review and remove or disable inactive guest accounts to reduce security risks.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
