using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Spam action set to move message to junk mail folder or quarantine (SpamAction in MoveToJmf/Quarantine).
    /// Port of Invoke-CippTestORCA139. Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA139 : ICippTest
    {
        public string Id => "ORCA139";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => !InSet(p, "SpamAction", "MoveToJmf", "Quarantine")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have Spam action set to move to Junk Email folder or Quarantine.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies do not have Spam action set appropriately.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "SpamAction") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Spam Action" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
