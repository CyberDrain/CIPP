using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 7.0.0 (2.1.8) — SPF records SHALL be published for all Exchange domains.
    /// PS reads Get-CIPPDomainAnalyser (the Domains table). The cache-only engine reads the
    /// DomainAnalyser reporting-cache type, which Set-CIPPDBCacheDomainAnalyser snapshots verbatim
    /// from that same Get-CIPPDomainAnalyser output (same fields: Domain, ActualSPFRecord). Empty/
    /// not-collected → Skipped, matching PS `-not $Results`.
    /// </summary>
    public sealed class CIS_2_1_8 : ICippTest
    {
        public string Id => "CIS_2_1_8";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var results = data.Get("DomainAnalyser");
            if (!CippTestHelpers.Any(results))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Domain Analyser results found for this tenant. Run the CIPP Domain Analyser to populate domain health data.");
            }

            var domains = CippTestHelpers.Items(results).ToList();
            var failing = new List<JsonElement>();
            foreach (var d in domains)
            {
                var spf = CippTestHelpers.Str(d, "ActualSPFRecord");
                // PS: IsNullOrWhiteSpace($_.ActualSPFRecord) -or $_.ActualSPFRecord -notmatch 'v=spf1'
                if (string.IsNullOrWhiteSpace(spf) ||
                    spf!.IndexOf("v=spf1", System.StringComparison.OrdinalIgnoreCase) < 0)
                {
                    failing.Add(d);
                }
            }

            if (failing.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {domains.Count} domain(s) have an SPF record published.");
            }

            var sb = new StringBuilder();
            sb.Append($"{failing.Count} of {domains.Count} domain(s) are missing a valid SPF record:\n\n| Domain | SPF Record |\n| :----- | :--------- |\n");
            foreach (var d in failing.Take(25))
            {
                sb.Append($"| {CippTestHelpers.Str(d, "Domain")} | {CippTestHelpers.Str(d, "ActualSPFRecord")} |\n");
            }
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
