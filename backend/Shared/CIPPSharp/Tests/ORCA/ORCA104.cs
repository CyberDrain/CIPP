using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// High Confidence Phish action set to Quarantine message. Port of Invoke-CippTestORCA104.
    /// Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA104 : ICippTest
    {
        public string Id => "ORCA104";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var passed = policies.Where(p => StrEq(p, "HighConfidencePhishAction", "Quarantine")).ToList();
            var failed = policies.Where(p => !StrEq(p, "HighConfidencePhishAction", "Quarantine")).ToList();

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have High Confidence Phish action set to Quarantine.\n\n");
                sb.Append($"**Compliant Policies:** {passed.Count}\n\n");
                if (passed.Count > 0)
                {
                    var rows = passed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "HighConfidencePhishAction") }).ToList();
                    sb.Append(Markdown.Table(new[] { "Policy Name", "Action" }, rows));
                }
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("Some anti-spam policies do not have High Confidence Phish action set to Quarantine.\n\n");
            f.Append($"**Failed Policies:** {failed.Count} | **Passed Policies:** {passed.Count}\n\n");
            f.Append("### Non-Compliant Policies\n\n");
            var frows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "HighConfidencePhishAction"), "Quarantine" }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Current Action", "Recommended Action" }, frows));
            f.Append("\n**Remediation:** Update the HighConfidencePhishAction to 'Quarantine' for enhanced security.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
