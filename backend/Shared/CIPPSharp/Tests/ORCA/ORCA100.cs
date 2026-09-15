using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Bulk Complaint Level threshold is between 4 and 6. Port of Invoke-CippTestORCA100.
    /// Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA100 : ICippTest
    {
        public string Id => "ORCA100";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => !(Int(p, "BulkThreshold") >= 4 && Int(p, "BulkThreshold") <= 6)).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have appropriate Bulk Complaint Level (BCL) thresholds set between 4 and 6.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies have BCL thresholds outside the recommended range (4-6).\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "BulkThreshold") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Current BCL Threshold" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
