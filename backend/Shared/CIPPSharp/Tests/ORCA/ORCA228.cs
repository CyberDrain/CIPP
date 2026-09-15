using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// No trusted senders in anti-phishing policies (ExcludedSenders is empty).
    /// Port of Invoke-CippTestORCA228. Single source: ExoAntiPhishPolicies.
    /// </summary>
    public sealed class ORCA228 : ICippTest
    {
        public string Id => "ORCA228";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAntiPhishPolicies"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoAntiPhishPolicies")).ToList();
            var failed = policies.Where(p => ArrayLen(p, "ExcludedSenders") > 0).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("No anti-phishing policies have trusted senders configured.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-phishing policies have trusted senders configured.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), ArrayLen(p, "ExcludedSenders").ToString() }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Excluded Senders Count" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
