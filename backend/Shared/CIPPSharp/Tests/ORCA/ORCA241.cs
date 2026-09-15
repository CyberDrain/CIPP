using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// First Contact Safety Tips is enabled (EnableFirstContactSafetyTips == true).
    /// Port of Invoke-CippTestORCA241. Single source: ExoAntiPhishPolicies.
    /// </summary>
    public sealed class ORCA241 : ICippTest
    {
        public string Id => "ORCA241";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAntiPhishPolicies"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoAntiPhishPolicies")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "EnableFirstContactSafetyTips")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-phishing policies have First Contact Safety Tips enabled.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-phishing policies do not have First Contact Safety Tips enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "EnableFirstContactSafetyTips") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Enable First Contact Safety Tips" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
