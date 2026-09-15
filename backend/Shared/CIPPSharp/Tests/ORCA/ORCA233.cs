using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Domains pointed at EOP or enhanced filtering used. Port of Invoke-CippTestORCA233.
    /// Single source: ExoAcceptedDomains. Authoritative (MX to EOP) or InternalRelay/ExternalRelay
    /// domains are treated as compliant; any other DomainType is flagged for review.
    /// </summary>
    public sealed class ORCA233 : ICippTest
    {
        public string Id => "ORCA233";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            var compliant = new List<string>();
            var nonCompliant = new List<string>();
            foreach (var domain in Items(data.Get("ExoAcceptedDomains")))
            {
                var name = Str(domain, "DomainName") ?? "";
                if (StrEq(domain, "DomainType", "Authoritative")
                    || InSet(domain, "DomainType", "InternalRelay", "ExternalRelay"))
                    compliant.Add(name);
                else
                    nonCompliant.Add(name);
            }

            if (nonCompliant.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All domains are properly configured for mail flow.\n\n");
                sb.Append($"**Compliant Domains:** {compliant.Count}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{nonCompliant.Count} domains may not be properly configured for mail flow.\n\n");
            f.Append("**Domains Needing Review:**\n\n");
            foreach (var name in nonCompliant)
                f.Append($"- {name}\n");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
