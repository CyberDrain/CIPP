using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Zero Hour Autopurge Enabled for Spam (SpamZapEnabled = true). Port of Invoke-CippTestORCA120_spam.
    /// Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA120_spam : ICippTest
    {
        public string Id => "ORCA120_spam";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "SpamZapEnabled")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have Zero Hour Autopurge for Spam enabled.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies do not have Zero Hour Autopurge for Spam enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "SpamZapEnabled") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Spam ZAP Enabled" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
