using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Similar Domains Safety Tips is enabled (EnableSimilarDomainsSafetyTips = true).
    /// Port of Invoke-CippTestORCA119. Single source: ExoAntiPhishPolicies.
    /// </summary>
    public sealed class ORCA119 : ICippTest
    {
        public string Id => "ORCA119";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAntiPhishPolicies"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoAntiPhishPolicies")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "EnableSimilarDomainsSafetyTips")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-phishing policies have Similar Domains Safety Tips enabled.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-phishing policies do not have Similar Domains Safety Tips enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "EnableSimilarDomainsSafetyTips") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Enable Similar Domains Safety Tips" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
