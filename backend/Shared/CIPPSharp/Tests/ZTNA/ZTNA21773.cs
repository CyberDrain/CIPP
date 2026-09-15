using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Applications do not have certificates with expiration longer than 180 days.
    /// Port of Invoke-CippTestZTNA21773. Apps + ServicePrincipals with any keyCredential whose
    /// endDateTime is more than 180 days out. Passed when none exist.
    /// </summary>
    public sealed class ZTNA21773 : ICippTest
    {
        public string Id => "ZTNA21773";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var apps = data.Get("Apps");
            var sps = data.Get("ServicePrincipals");

            if (!Any(apps) && !Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var maxDate = DateTimeOffset.Now.AddDays(180);

            var appsLong = new List<JsonElement>();
            foreach (var a in Items(apps)) if (HasLongCert(a, maxDate)) appsLong.Add(a);

            var spsLong = new List<JsonElement>();
            foreach (var s in Items(sps)) if (HasLongCert(s, maxDate)) spsLong.Add(s);

            if (appsLong.Count + spsLong.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "Applications in your tenant do not have certificates valid for more than 180 days");

            var sb = new StringBuilder();
            sb.Append($"Found {appsLong.Count} applications and {spsLong.Count} service principals with certificates longer than 180 days\n\n");
            if (appsLong.Count > 0)
            {
                sb.Append("## Apps with long-lived certificates:\n\n");
                sb.Append(JoinAppLines(appsLong));
                sb.Append("\n\n");
            }
            if (spsLong.Count > 0)
            {
                sb.Append("## Service principals with long-lived certificates:\n\n");
                sb.Append(JoinAppLines(spsLong));
            }
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        private static bool HasLongCert(JsonElement app, DateTimeOffset maxDate)
        {
            if (!HasCredentials(app, "keyCredentials")) return false;
            foreach (var cred in Arr(app, "keyCredentials"))
            {
                var end = Str(cred, "endDateTime");
                if (string.IsNullOrEmpty(end)) continue;
                if (DateTimeOffset.TryParse(end, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt)
                    && dt > maxDate)
                    return true;
            }
            return false;
        }

        private static string JoinAppLines(List<JsonElement> items)
        {
            var lines = new List<string>(items.Count);
            foreach (var e in items) lines.Add($"- {Text(e, "displayName")} (AppId: {Text(e, "appId")})");
            return string.Join("\n", lines);
        }
    }
}
