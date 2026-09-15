using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Important protection alerts enabled. Port of Invoke-CippTestORCA242.
    /// Single source: ExoProtectionAlert. Checks the AIR-related alert set; alerts not deployed to the
    /// tenant are ignored, deployed ones must not be Disabled. All-absent → Skipped.
    /// </summary>
    public sealed class ORCA242 : ICippTest
    {
        public string Id => "ORCA242";

        private static readonly string[] ImportantAlerts =
        {
            "A potentially malicious URL click was detected",
            "Teams message reported by user as security risk",
            "Email messages containing phish URLs removed after delivery",
            "Suspicious Email Forwarding Activity",
            "Malware not zapped because ZAP is disabled",
            "Phish delivered due to an ETR override",
            "Email messages containing malicious file removed after delivery",
            "Email reported by user as malware or phish",
            "Email messages containing malicious URL removed after delivery",
            "Email messages containing malware removed after delivery",
            "A user clicked through to a potentially malicious URL",
            "Email messages from a campaign removed after delivery",
            "Email messages removed after delivery",
            "Suspicious email sending patterns detected"
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoProtectionAlert"))
                return new CippTestResult(TestStatus.Skipped,
                    "No protection alert data found. This may be due to missing required licenses or data collection not yet completed.");

            var alerts = Items(data.Get("ExoProtectionAlert")).ToList();
            var passed = new List<JsonElement>();
            var failed = new List<JsonElement>();

            foreach (var name in ImportantAlerts)
            {
                JsonElement? found = alerts.Where(a => StrEq(a, "Name", name))
                    .Select(a => (JsonElement?)a).FirstOrDefault();
                if (!found.HasValue) continue;

                if (IsTrue(found.Value, "Disabled")) failed.Add(found.Value);
                else passed.Add(found.Value);
            }

            if (failed.Count == 0 && passed.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "None of the AIR-related protection alerts are deployed to this tenant. This may indicate missing Defender for Office 365 licensing.");

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All AIR-related protection alerts deployed to this tenant are enabled.\n\n");
                sb.Append($"**Enabled Alerts:** {passed.Count}\n\n");
                var prows = passed.Select(a => (IReadOnlyList<string>)new[] { CellOf(a, "Name") }).ToList();
                sb.Append(Markdown.Table(new[] { "Alert Name" }, prows));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} AIR-related protection alerts are disabled.\n\n");
            f.Append($"**Disabled:** {failed.Count} | **Enabled:** {passed.Count}\n\n");
            f.Append("### Disabled Alerts\n\n");
            var frows = failed.Select(a => (IReadOnlyList<string>)new[] { CellOf(a, "Name"), CellOf(a, "Disabled") }).ToList();
            f.Append(Markdown.Table(new[] { "Alert Name", "Disabled" }, frows));
            f.Append("\n**Remediation:** Re-enable these alert policies. Automated Incident Response (AIR) triggers from them and cannot function correctly when they are disabled.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
