using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.9) — DKIM SHALL be enabled for all Exchange Online Domains.
    /// Port of Invoke-CippTestCIS_2_1_9. Joins accepted (sending) domains to the DKIM signing
    /// config by domain name.
    /// </summary>
    public sealed class CIS_2_1_9 : ICippTest
    {
        public string Id => "CIS_2_1_9";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var dkim = data.Get("ExoDkimSigningConfig");
            var accepted = data.Get("ExoAcceptedDomains");

            if (!Any(dkim) || !Any(accepted))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (ExoDkimSigningConfig or ExoAcceptedDomains) not found. Please refresh the cache for this tenant.");
            }

            // Sending domains: SendingFromDomainDisabled falsy and not an *.onmicrosoft.com domain.
            var sending = new List<JsonElement>();
            foreach (var a in accepted.EnumerateArray())
            {
                if (!PsTruthyProp(a, "SendingFromDomainDisabled")
                    && NotLikeCI(Str(a, "DomainName"), "*onmicrosoft.com"))
                {
                    sending.Add(a);
                }
            }

            // First DKIM config per domain (case-insensitive), matching Group-Object -AsHashTable.
            var dkimByDomain = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var d in dkim.EnumerateArray())
            {
                var domain = Str(d, "Domain");
                if (!string.IsNullOrEmpty(domain) && !dkimByDomain.ContainsKey(domain!))
                    dkimByDomain[domain!] = d;
            }

            var failed = new List<(string Domain, string Enabled)>();
            foreach (var s in sending)
            {
                var name = Str(s, "DomainName") ?? "";
                JsonElement? cfg = (name.Length > 0 && dkimByDomain.TryGetValue(name, out var c)) ? c : (JsonElement?)null;
                if (cfg == null || !IsTrue(cfg.Value, "Enabled"))
                {
                    failed.Add((name, cfg == null ? "" : Cell(Prop(cfg.Value, "Enabled"))));
                }
            }

            if (failed.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"DKIM is enabled for all {sending.Count} sending domain(s).");
            }

            var sb = new StringBuilder();
            sb.Append($"DKIM is not enabled for {failed.Count} sending domain(s):\n\n");
            var rows = new List<IReadOnlyList<string>>();
            foreach (var f in failed) rows.Add(new[] { f.Domain, f.Enabled });
            sb.Append(Markdown.Table(new[] { "Domain", "DKIM Enabled" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
