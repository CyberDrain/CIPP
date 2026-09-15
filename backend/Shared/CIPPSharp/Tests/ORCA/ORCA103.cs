using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Outbound spam filter policy settings configured. Port of Invoke-CippTestORCA103.
    /// Single source: ExoHostedOutboundSpamFilterPolicy. Numeric comparisons coerce absent → 0
    /// (matching PS <c>$null -le 0</c>).
    /// </summary>
    public sealed class ORCA103 : ICippTest
    {
        public string Id => "ORCA103";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedOutboundSpamFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedOutboundSpamFilterPolicy")).ToList();
            var failed = new List<(System.Text.Json.JsonElement Policy, List<string> Issues)>();
            int passedCount = 0;

            foreach (var p in policies)
            {
                var issues = new List<string>();
                var ext = Int(p, "RecipientLimitExternalPerHour");
                if (ext <= 0 || ext > 500)
                    issues.Add($"RecipientLimitExternalPerHour: {CellOf(p, "RecipientLimitExternalPerHour")} (should be between 1 and 500)");
                var intl = Int(p, "RecipientLimitInternalPerHour");
                if (intl <= 0 || intl > 1000)
                    issues.Add($"RecipientLimitInternalPerHour: {CellOf(p, "RecipientLimitInternalPerHour")} (should be between 1 and 1000)");
                if (!StrEq(p, "ActionWhenThresholdReached", "BlockUser"))
                    issues.Add($"ActionWhenThresholdReached: {CellOf(p, "ActionWhenThresholdReached")} (should be BlockUser)");

                if (issues.Count == 0) passedCount++;
                else failed.Add((p, issues));
            }

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All outbound spam filter policies are configured correctly.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} outbound spam filter policies are not configured correctly.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(x => (IReadOnlyList<string>)new[] { CellOf(x.Policy, "Identity"), string.Join("<br/>", x.Issues) }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Issues" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
