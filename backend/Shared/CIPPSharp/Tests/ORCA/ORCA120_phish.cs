using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Zero Hour Autopurge Enabled for Phish (PhishZapEnabled = true). Port of Invoke-CippTestORCA120_phish.
    /// Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA120_phish : ICippTest
    {
        public string Id => "ORCA120_phish";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "PhishZapEnabled")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have Zero Hour Autopurge for Phish enabled.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies do not have Zero Hour Autopurge for Phish enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "PhishZapEnabled") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Phish ZAP Enabled" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
