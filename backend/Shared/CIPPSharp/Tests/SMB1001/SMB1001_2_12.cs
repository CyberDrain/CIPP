using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.12) — SPF, DKIM and DMARC on every custom sending domain. Port of
    /// Invoke-CippTestSMB1001_2_12. Joins DomainAnalyser (SPF/DMARC) + ExoDkimSigningConfig
    /// (DKIM) + ExoAcceptedDomains (which domains send). Level 3 wants p=reject/quarantine.
    /// </summary>
    public sealed class SMB1001_2_12 : ICippTest
    {
        public string Id => "SMB1001_2_12";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var analyser = data.Get("DomainAnalyser");
            var dkim = data.Get("ExoDkimSigningConfig");
            var accepted = data.Get("ExoAcceptedDomains");

            if (!Any(analyser) || !Any(accepted))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required data (Domain Analyser or ExoAcceptedDomains) not found. Run the CIPP Domain Analyser and refresh caches.");
            }

            var analyserByDomain = FirstWinsByKey(analyser, "Domain");
            var dkimByDomain = FirstWinsByKey(dkim, "Domain");

            var sending = new List<JsonElement>();
            foreach (var d in Items(accepted))
            {
                if (IsTrue(d, "SendingFromDomainDisabled")) continue;
                if (Like(Str(d, "DomainName"), "*onmicrosoft.com")) continue;
                sending.Add(d);
            }

            var failures = new List<(string domain, string spf, string dkim, string dmarc, string issues)>();
            foreach (var d in sending)
            {
                var domainName = Str(d, "DomainName") ?? "";
                analyserByDomain.TryGetValue(domainName.ToLowerInvariant(), out var a);
                dkimByDomain.TryGetValue(domainName.ToLowerInvariant(), out var k);

                bool spf = Contains(Str(a, "ActualSPFRecord"), "v=spf1");
                bool dmarc = IsTrue(a, "DMARCPresent") || Contains(Str(a, "DMARCFullPolicy"), "v=DMARC1");
                bool dmarcStrong = StrEq(a, "DMARCActionPolicy", "Reject")
                                   || StrEq(a, "DMARCActionPolicy", "Quarantine")
                                   || Match(Str(a, "DMARCFullPolicy"), @"p\s*=\s*(reject|quarantine)");
                bool dkimEnabled = k.ValueKind == JsonValueKind.Object && IsTrue(k, "Enabled");

                var domainIssues = new List<string>();
                if (!spf) domainIssues.Add("no SPF");
                if (!dkimEnabled) domainIssues.Add("no DKIM");
                if (!dmarc) domainIssues.Add("no DMARC");
                else if (!dmarcStrong) domainIssues.Add("DMARC weak (not p=reject/quarantine)");

                if (domainIssues.Count > 0)
                {
                    var dmarcCell = dmarc ? (dmarcStrong ? "✅" : "⚠️") : "❌";
                    failures.Add((domainName, spf ? "✅" : "❌", dkimEnabled ? "✅" : "❌", dmarcCell,
                        string.Join(", ", domainIssues)));
                }
            }

            if (sending.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "No custom sending domains configured.");
            }

            if (failures.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {sending.Count} sending domain(s) have SPF, DKIM, and DMARC (p=reject or p=quarantine) configured.");
            }

            var sb = new StringBuilder();
            sb.Append($"{failures.Count} of {sending.Count} sending domain(s) are missing email authentication:\n\n");
            var rows = new List<IReadOnlyList<string>>();
            int shown = 0;
            foreach (var f in failures)
            {
                if (shown++ >= 25) break;
                rows.Add(new[] { f.domain, f.spf, f.dkim, f.dmarc, f.issues });
            }
            sb.Append(Markdown.Table(new[] { "Domain", "SPF", "DKIM", "DMARC", "Issues" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
        }

        /// <summary>Lookup keyed by a lowercased string field, first occurrence winning (Select -First 1).</summary>
        private static Dictionary<string, JsonElement> FirstWinsByKey(JsonElement arr, string keyField)
        {
            var d = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var e in Items(arr))
            {
                var key = Str(e, keyField);
                if (string.IsNullOrEmpty(key)) continue;
                var lk = key!.ToLowerInvariant();
                if (!d.ContainsKey(lk)) d[lk] = e;
            }
            return d;
        }
    }
}
