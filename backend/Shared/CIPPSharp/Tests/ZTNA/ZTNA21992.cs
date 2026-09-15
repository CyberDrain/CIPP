using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Application certificates must be rotated on a regular basis.
    /// Port of Invoke-CippTestZTNA21992. Skipped when both Apps and ServicePrincipals are absent.
    /// Flags apps/SPs whose oldest key-credential start date is more than 180 days ago.
    /// </summary>
    public sealed class ZTNA21992 : ICippTest
    {
        public string Id => "ZTNA21992";
        private const int RotationThresholdDays = 180;

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var apps = data.Get("Apps");
            var sps = data.Get("ServicePrincipals");

            if (!Any(apps) && !Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var now = DateTimeOffset.Now;
            var thresholdDate = now.AddDays(-RotationThresholdDays);

            var oldApps = CollectOld(apps, thresholdDate);
            var oldSps = CollectOld(sps, thresholdDate);

            if (oldApps.Count == 0 && oldSps.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"Certificates for applications in your tenant have been issued within {RotationThresholdDays} days");

            var lines = new List<string>
            {
                $"Found {oldApps.Count} application(s) and {oldSps.Count} service principal(s) with certificates not rotated within {RotationThresholdDays} days.",
                "",
                $"**Certificate rotation threshold:** {RotationThresholdDays} days",
                ""
            };

            if (oldApps.Count > 0)
            {
                lines.Add("**Applications with old certificates:**");
                AppendItems(lines, oldApps, now, "application(s)");
                lines.Add("");
            }

            if (oldSps.Count > 0)
            {
                lines.Add("**Service principals with old certificates:**");
                AppendItems(lines, oldSps, now, "service principal(s)");
                lines.Add("");
            }

            lines.Add("**Recommendation:** Rotate certificates regularly to reduce the risk of credential compromise.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }

        private static List<(string DisplayName, DateTimeOffset Oldest)> CollectOld(JsonElement records, DateTimeOffset threshold)
        {
            var result = new List<(string, DateTimeOffset)>();
            foreach (var rec in Items(records))
            {
                if (ArrayLen(rec, "keyCredentials") == 0) continue;
                DateTimeOffset? oldest = null;
                foreach (var cred in Arr(rec, "keyCredentials"))
                {
                    var start = ParseDateProp(cred, "startDateTime");
                    if (start is null) continue;
                    if (oldest is null || start.Value < oldest.Value) oldest = start;
                }
                if (oldest is not null && oldest.Value < threshold)
                    result.Add((Text(rec, "displayName"), oldest.Value));
            }
            return result;
        }

        private static void AppendItems(List<string> lines, List<(string DisplayName, DateTimeOffset Oldest)> items,
            DateTimeOffset now, string noun)
        {
            for (int i = 0; i < items.Count && i < 10; i++)
            {
                var daysOld = Round0((now - items[i].Oldest).TotalDays).ToString("0", CultureInfo.InvariantCulture);
                lines.Add($"- {items[i].DisplayName} (Certificate age: {daysOld} days)");
            }
            if (items.Count > 10)
                lines.Add($"- ... and {items.Count - 10} more {noun}");
        }
    }
}
