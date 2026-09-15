using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// DNS records have been set up to support DKIM (Selector1CNAME + Selector2CNAME present).
    /// Port of Invoke-CippTestORCA108_1. Joins ExoDkimSigningConfig with ExoAcceptedDomains.
    /// Note: this test excludes '*onmicrosoft.com' (no leading dot), unlike ORCA108.
    /// </summary>
    public sealed class ORCA108_1 : ICippTest
    {
        public string Id => "ORCA108_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoDkimSigningConfig") || !data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var dkim = Items(data.Get("ExoDkimSigningConfig")).ToList();
            var custom = Items(data.Get("ExoAcceptedDomains"))
                .Where(d => !Like(Str(d, "DomainName"), "*onmicrosoft.com")).ToList();

            var passedDomains = new List<JsonElement>();
            var failedDomains = new List<JsonElement>();
            foreach (var domain in custom)
            {
                var name = Str(domain, "DomainName");
                JsonElement? rec = dkim.Where(r => string.Equals(Str(r, "Domain"), name, StringComparison.OrdinalIgnoreCase))
                    .Select(r => (JsonElement?)r).FirstOrDefault();
                if (rec.HasValue && HasText(rec.Value, "Selector1CNAME") && HasText(rec.Value, "Selector2CNAME"))
                    passedDomains.Add(domain);
                else
                    failedDomains.Add(domain);
            }

            if (failedDomains.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All custom domains have DKIM DNS records configured.\n\n");
                sb.Append($"**Compliant Domains:** {passedDomains.Count}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failedDomains.Count} custom domains do not have DKIM DNS records configured.\n\n");
            f.Append($"**Non-Compliant Domains:** {failedDomains.Count}\n\n");
            var rows = failedDomains.Select(d => (IReadOnlyList<string>)new[] { CellOf(d, "DomainName") }).ToList();
            f.Append(Markdown.Table(new[] { "Domain Name" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
