using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 7.0.0 (2.1.10) — DMARC records (p=quarantine or p=reject) SHALL be published for all
    /// Exchange Online domains. Reads the DomainAnalyser reporting-cache type (snapshot of
    /// Get-CIPPDomainAnalyser: Domain, DMARCPresent, DMARCActionPolicy). Empty/not-collected →
    /// Skipped, matching PS `-not $Results`.
    /// </summary>
    public sealed class CIS_2_1_10 : ICippTest
    {
        public string Id => "CIS_2_1_10";

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
                // PS: $_.DMARCPresent -ne $true -or $_.DMARCActionPolicy -notin ('quarantine','reject')
                var policy = CippTestHelpers.Str(d, "DMARCActionPolicy");
                var acceptable = string.Equals(policy, "quarantine", System.StringComparison.OrdinalIgnoreCase)
                              || string.Equals(policy, "reject", System.StringComparison.OrdinalIgnoreCase);
                if (!CippTestHelpers.IsTrue(d, "DMARCPresent") || !acceptable)
                {
                    failing.Add(d);
                }
            }

            if (failing.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {domains.Count} domain(s) have a DMARC record with p=quarantine or p=reject.");
            }

            var sb = new StringBuilder();
            sb.Append($"{failing.Count} of {domains.Count} domain(s) are missing a compliant DMARC record:\n\n| Domain | DMARCPresent | DMARCActionPolicy |\n| :----- | :----------- | :---------------- |\n");
            foreach (var d in failing.Take(25))
            {
                sb.Append($"| {CippTestHelpers.Str(d, "Domain")} | {CippTestHelpers.Cell(CippTestHelpers.Prop(d, "DMARCPresent"))} | {CippTestHelpers.Str(d, "DMARCActionPolicy")} |\n");
            }
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
