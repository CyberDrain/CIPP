using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Domains not allow listed in Transport Rules. Port of Invoke-CippTestORCA118_2.
    /// Single source: ExoTransportRules. A rule fails if it sets SCL to -1 based on sender domain.
    /// </summary>
    public sealed class ORCA118_2 : ICippTest
    {
        public string Id => "ORCA118_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoTransportRules"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var rules = Items(data.Get("ExoTransportRules")).ToList();
            var failed = rules.Where(r => Int(r, "SetSCL") == -1 && Truthy(r, "SenderDomainIs")).ToList();

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("No transport rules allow list domains by setting SCL to -1.\n\n");
                sb.Append($"**Total Transport Rules Checked:** {rules.Count}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} transport rules allow list domains by setting SCL to -1.\n\n");
            f.Append($"**Non-Compliant Rules:** {failed.Count}\n\n");
            var rows = failed.Select(r =>
            {
                var domains = StringValues(r, "SenderDomainIs").ToList();
                var display = domains.Count > 0 ? string.Join(", ", domains) : "N/A";
                return (IReadOnlyList<string>)new[] { CellOf(r, "Name"), display };
            }).ToList();
            f.Append(Markdown.Table(new[] { "Rule Name", "Sender Domains" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
