using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Xml;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// End-user spam notification is enabled on the Global Quarantine policy.
    /// Port of Invoke-CippTestORCA107. Single source: ExoGlobalQuarantinePolicy.
    /// EndUserSpamNotificationFrequency is an ISO-8601 duration ('PT4H','P1D','P7D'); 'PT0S'/null
    /// means disabled, and Name 'DefaultGlobalPolicy' means never configured.
    /// </summary>
    public sealed class ORCA107 : ICippTest
    {
        public string Id => "ORCA107";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoGlobalQuarantinePolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoGlobalQuarantinePolicy")).ToList();
            var passed = new List<(JsonElement Policy, string Freq)>();
            var failed = new List<(JsonElement Policy, string Freq)>();

            foreach (var p in policies)
            {
                var frequency = Str(p, "EndUserSpamNotificationFrequency");
                bool isConfigured = !string.Equals(Str(p, "Name"), "DefaultGlobalPolicy", StringComparison.OrdinalIgnoreCase);
                bool isEnabled = false;
                if (isConfigured && !string.IsNullOrEmpty(frequency))
                {
                    try { isEnabled = XmlConvert.ToTimeSpan(frequency!).TotalSeconds > 0; }
                    catch { isEnabled = false; }
                }
                var display = !string.IsNullOrEmpty(frequency) ? frequency! : "Not set";
                if (isEnabled) passed.Add((p, display));
                else failed.Add((p, display));
            }

            if (failed.Count == 0 && passed.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append("The Global Quarantine policy has end-user spam notifications enabled.\n\n");
                var rows = passed.Select(x => (IReadOnlyList<string>)new[] { CellOf(x.Policy, "Identity"), x.Freq }).ToList();
                sb.Append(Markdown.Table(new[] { "Policy Name", "Notification Frequency" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("The Global Quarantine policy does not have end-user spam notifications enabled.\n\n");
            var frows = failed.Select(x => (IReadOnlyList<string>)new[] { CellOf(x.Policy, "Identity"), x.Freq }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Notification Frequency" }, frows));
            f.Append("\n**Remediation:** Configure the Global Quarantine policy with a notification frequency (e.g. PT4H, P1D, or P7D) via `Set-QuarantinePolicy -EndUserSpamNotificationFrequency`.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
