using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Internal Sender notifications are disabled (checks InlineSafetyTipsEnabled = true).
    /// Port of Invoke-CippTestORCA110. Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA110 : ICippTest
    {
        public string Id => "ORCA110";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "InlineSafetyTipsEnabled")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have internal sender notifications disabled.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies have internal sender notifications enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "InlineSafetyTipsEnabled") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Inline Safety Tips Enabled" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
