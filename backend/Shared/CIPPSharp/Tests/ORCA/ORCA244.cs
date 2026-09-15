using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Policies honor sending domain DMARC (HonorDmarcPolicy == true).
    /// Port of Invoke-CippTestORCA244. Single source: ExoAntiPhishPolicies.
    /// </summary>
    public sealed class ORCA244 : ICippTest
    {
        public string Id => "ORCA244";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAntiPhishPolicies"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoAntiPhishPolicies")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "HonorDmarcPolicy")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-phishing policies honor sending domain DMARC.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-phishing policies do not honor sending domain DMARC.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "HonorDmarcPolicy") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Honor DMARC Policy" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
