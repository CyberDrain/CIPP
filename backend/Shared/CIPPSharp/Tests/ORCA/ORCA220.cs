using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Advanced Phish filter threshold level is adequate (PhishThresholdLevel &gt;= 2).
    /// Port of Invoke-CippTestORCA220. Single source: ExoAntiPhishPolicies. PhishThresholdLevel is a
    /// number (1=Standard, 2=Aggressive, 3=More Aggressive, 4=Most Aggressive); absent → 0 → below.
    /// </summary>
    public sealed class ORCA220 : ICippTest
    {
        public string Id => "ORCA220";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAntiPhishPolicies"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoAntiPhishPolicies")).ToList();
            var failed = policies.Where(p => !(Int(p, "PhishThresholdLevel") >= 2)).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-phishing policies have adequate phishing threshold levels (2 or higher).\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-phishing policies have inadequate phishing threshold levels.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "PhishThresholdLevel") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Phish Threshold Level" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
