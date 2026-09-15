using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Authenticated Receive Chain for non-EOP domains. Port of Invoke-CippTestORCA243.
    /// Single source: ExoAcceptedDomains. Non-authoritative (InternalRelay/ExternalRelay) domains need
    /// inbound connectors with proper authentication — reported as Informational, never Failed.
    /// </summary>
    public sealed class ORCA243 : ICippTest
    {
        public string Id => "ORCA243";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            var domains = Items(data.Get("ExoAcceptedDomains")).ToList();
            var nonAuth = domains.Where(d => InSet(d, "DomainType", "InternalRelay", "ExternalRelay")).ToList();

            if (nonAuth.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All domains are authoritative. No inbound connectors needed.\n\n");
                sb.Append($"**Total Domains:** {domains.Count}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var i = new StringBuilder();
            i.Append($"Found {nonAuth.Count} non-authoritative domains.\n\n");
            i.Append("**Domains Requiring Inbound Connectors:**\n\n");
            foreach (var domain in nonAuth)
                i.Append($"- {CellOf(domain, "DomainName")} (Type: {CellOf(domain, "DomainType")})\n");
            i.Append("\n**Action Required:** Verify inbound connectors are configured with proper authentication for these domains");
            return new CippTestResult(TestStatus.Informational, i.ToString());
        }
    }
}
