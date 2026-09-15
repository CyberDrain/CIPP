using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Own domains not allow listed in Transport Rules. Port of Invoke-CippTestORCA118_4.
    /// Joins ExoTransportRules with ExoAcceptedDomains: a rule fails if it sets SCL to -1 for one of
    /// the tenant's own accepted domains.
    /// </summary>
    public sealed class ORCA118_4 : ICippTest
    {
        public string Id => "ORCA118_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoTransportRules"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            var ownDomains = new HashSet<string>(
                Items(data.Get("ExoAcceptedDomains")).Select(d => Str(d, "DomainName") ?? "").Where(s => s.Length > 0),
                StringComparer.OrdinalIgnoreCase);

            var rules = Items(data.Get("ExoTransportRules")).ToList();
            var failed = new List<(System.Text.Json.JsonElement Rule, List<string> Own)>();
            foreach (var r in rules)
            {
                if (Int(r, "SetSCL") == -1 && Truthy(r, "SenderDomainIs"))
                {
                    var ownInRule = StringValues(r, "SenderDomainIs").Where(d => ownDomains.Contains(d)).ToList();
                    if (ownInRule.Count > 0) failed.Add((r, ownInRule));
                }
            }

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("No transport rules allow list own domains by setting SCL to -1.\n\n");
                sb.Append($"**Total Transport Rules Checked:** {rules.Count}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} transport rules allow list own domains by setting SCL to -1.\n\n");
            f.Append($"**Non-Compliant Rules:** {failed.Count}\n\n");
            var rows = failed.Select(x => (IReadOnlyList<string>)new[] { CellOf(x.Rule, "Name"), string.Join(", ", x.Own) }).ToList();
            f.Append(Markdown.Table(new[] { "Rule Name", "Own Domains in Rule" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
