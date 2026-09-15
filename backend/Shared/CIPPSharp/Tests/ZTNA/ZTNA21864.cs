using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All risk detections are triaged.
    /// Port of Invoke-CippTestZTNA21864. Skipped on no RiskDetections data. A detection is untriaged
    /// when its riskState is not one of remediated/dismissed/confirmedSafe/none AND it is older than
    /// 30 days. Passed when none remain untriaged.
    /// </summary>
    public sealed class ZTNA21864 : ICippTest
    {
        public string Id => "ZTNA21864";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var detections = data.Get("RiskDetections");
            if (!Any(detections))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var threshold = DateTimeOffset.Now.AddDays(-30);
            int total = detections.GetArrayLength();

            var untriaged = new List<(JsonElement Detection, string When, DateTimeOffset Sort)>();
            foreach (var d in Items(detections))
            {
                if (PropIn(d, "riskState", "remediated", "dismissed", "confirmedSafe", "none")) continue;
                var when = Str(d, "detectedDateTime") ?? Str(d, "activityDateTime");
                if (string.IsNullOrEmpty(when)) continue;
                var parsed = ParseDate(when);
                if (parsed is null) continue; // PS: unparseable [DateTime] cast throws and is swallowed
                if (parsed.Value < threshold) untriaged.Add((d, when!, parsed.Value));
            }

            if (untriaged.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {total} risk detection(s) have been triaged or are recent (within 30 days).");

            var lines = new List<string>
            {
                $"{untriaged.Count} risk detection(s) older than 30 days remain in an untriaged state.",
                "",
                $"**Total detections:** {total}",
                $"**Untriaged (>30 days):** {untriaged.Count}",
                "",
                "| User | Risk Event | Risk Level | Risk State | Detected |",
                "| :--- | :--------- | :--------- | :--------- | :------- |"
            };

            foreach (var entry in untriaged.OrderBy(e => e.Sort).Take(25))
            {
                var d = entry.Detection;
                lines.Add($"| {Str(d, "userDisplayName") ?? "-"} | {Str(d, "riskEventType") ?? "-"} | {Str(d, "riskLevel") ?? "-"} | {Str(d, "riskState") ?? "-"} | {entry.When} |");
            }

            if (untriaged.Count > 25)
            {
                lines.Add("");
                lines.Add($"...and {untriaged.Count - 25} more.");
            }

            lines.Add("");
            lines.Add("**Remediation:** Investigate and triage the listed risk detections through the Microsoft Entra ID Protection portal. Resolve each by marking the user as compromised, dismissing, or confirming safe.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
