using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Quarantine retention period is 30 days (checks &gt; 15). Port of Invoke-CippTestORCA106.
    /// Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA106 : ICippTest
    {
        public string Id => "ORCA106";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => !(Int(p, "QuarantineRetentionPeriod") > 15)).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have quarantine retention period set to 30 days.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies do not have quarantine retention period set to 30 days.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), $"{CellOf(p, "QuarantineRetentionPeriod")} days" }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Quarantine Retention Period" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
