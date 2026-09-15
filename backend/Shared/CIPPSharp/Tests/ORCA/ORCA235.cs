using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SPF records set up for custom domains. Port of Invoke-CippTestORCA235.
    /// PS reads Get-CIPPDomainAnalyser; the cache equivalent is CippReportingDB type
    /// <c>DomainAnalyser</c> (Set-CIPPDBCacheDomainAnalyser snapshots the analyser results there, and
    /// skips writing when the analyser has not run — so an absent type mirrors PS's empty-results Skip).
    /// Custom domains (Domain not -like '*.onmicrosoft.com') must publish an SPF record starting with
    /// v=spf1 and ending in -all (hard fail).
    /// </summary>
    public sealed class ORCA235 : ICippTest
    {
        public string Id => "ORCA235";

        private static readonly Regex SpfPrefix = new("v=spf1", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex HardFail = new(@"-all\s*$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("DomainAnalyser"))
                return new CippTestResult(TestStatus.Skipped,
                    "No Domain Analyser results found for this tenant. Run the CIPP Domain Analyser to populate domain health data.");

            var custom = Items(data.Get("DomainAnalyser"))
                .Where(d => !Like(Str(d, "Domain"), "*.onmicrosoft.com")).ToList();

            if (custom.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No custom domains found. Only onmicrosoft.com in use.");

            var passed = new List<JsonElement>();
            var failed = new List<JsonElement>();
            foreach (var domain in custom)
            {
                var spf = Str(domain, "ActualSPFRecord") ?? "";
                if (SpfPrefix.IsMatch(spf) && HardFail.IsMatch(spf))
                    passed.Add(domain);
                else
                    failed.Add(domain);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {passed.Count} custom domains have a valid SPF record ending in -all.");

            var f = new StringBuilder();
            f.Append($"{failed.Count} of {custom.Count} custom domains are missing a valid SPF record or do not end in -all (hard fail).\n\n");
            var rows = failed.Take(25).Select(d =>
            {
                var spf = Str(d, "ActualSPFRecord");
                var display = string.IsNullOrWhiteSpace(spf) ? "*(none)*" : spf;
                return (IReadOnlyList<string>)new[] { CellOf(d, "Domain"), display };
            }).ToList();
            f.Append(Markdown.Table(new[] { "Domain", "SPF Record" }, rows));
            f.Append("\n**Remediation:** Publish an SPF TXT record ending in -all (hard fail). For Microsoft 365 only: v=spf1 include:spf.protection.outlook.com -all. If routing through a third-party gateway, include that provider alongside, but keep -all at the end. Avoid ~all, ?all, and especially +all.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
