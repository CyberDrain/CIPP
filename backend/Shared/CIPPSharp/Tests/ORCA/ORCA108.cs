using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// DKIM signing is set up for all custom domains. Port of Invoke-CippTestORCA108.
    /// Joins ExoDkimSigningConfig with ExoAcceptedDomains on Domain/DomainName.
    /// </summary>
    public sealed class ORCA108 : ICippTest
    {
        public string Id => "ORCA108";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoDkimSigningConfig") || !data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var accepted = Items(data.Get("ExoAcceptedDomains")).ToList();
            var custom = accepted.Where(d =>
            {
                var name = Str(d, "DomainName");
                return !Like(name, "*.onmicrosoft.com") && !Like(name, "*.mail.onmicrosoft.com");
            }).ToList();

            if (custom.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No custom domains configured. DKIM check not applicable for default domains only.");

            // Group DKIM records by Domain (first per domain, case-insensitive) — Group-Object -AsHashTable -AsString then [0].
            var dkimByDomain = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var d in Items(data.Get("ExoDkimSigningConfig")))
            {
                var key = Str(d, "Domain");
                if (key != null && !dkimByDomain.ContainsKey(key)) dkimByDomain[key] = d;
            }

            var withDkim = new List<string>();
            var withoutDkim = new List<string>();
            foreach (var domain in custom)
            {
                var name = Str(domain, "DomainName") ?? "";
                if (dkimByDomain.TryGetValue(name, out var rec) && IsTrue(rec, "Enabled"))
                    withDkim.Add(name);
                else
                    withoutDkim.Add(name);
            }

            if (withoutDkim.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append($"DKIM signing is enabled for all custom domains ({withDkim.Count} domains).\n\n");
                sb.Append("**Domains with DKIM enabled:**\n");
                sb.Append(string.Join("\n", withDkim.Select(x => $"- {x}")));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("DKIM signing is not configured for all custom domains.\n\n");
            f.Append($"**Missing DKIM:** {withoutDkim.Count} | **Configured:** {withDkim.Count}\n\n");
            f.Append("### Domains without DKIM:\n");
            f.Append(string.Join("\n", withoutDkim.Select(x => $"- {x}")));
            f.Append("\n\n**Remediation:** Enable DKIM signing for all custom domains to prevent email spoofing.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
