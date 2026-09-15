using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.3.1 — DKIM SHOULD be enabled for all domains.
    /// Port of Invoke-CippTestCISAMSEXO31. Joins ExoDkimSigningConfig to the non-internal accepted
    /// domains (<c>-not SendingFromDomainDisabled</c>) on Domain name; a domain fails when it has no
    /// DKIM config or its config is not <c>Enabled</c> (PS truthiness).
    /// </summary>
    public sealed class CISAMSEXO31 : ICippTest
    {
        public string Id => "CISAMSEXO31";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var dkimConfigs = data.Get("ExoDkimSigningConfig");
            var acceptedDomains = data.Get("ExoAcceptedDomains");

            if (!Any(dkimConfigs) || !Any(acceptedDomains))
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (ExoDkimSigningConfig or ExoAcceptedDomains) not found. Please refresh the cache for this tenant.");

            // DKIM config lookup keyed on Domain (case-insensitive), first match wins.
            var dkimByDomain = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var c in Items(dkimConfigs))
            {
                var dom = Str(c, "Domain");
                if (!string.IsNullOrEmpty(dom) && !dkimByDomain.ContainsKey(dom!)) dkimByDomain[dom!] = c;
            }

            // Non-internal sending domains.
            var sendingDomains = new List<JsonElement>();
            foreach (var d in Items(acceptedDomains))
                if (NotTruthyProp(d, "SendingFromDomainDisabled")) sendingDomains.Add(d);

            if (sendingDomains.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: No sending domains found to check DKIM configuration.");

            var failed = new List<(string Domain, string Enabled, string Status)>();
            foreach (var d in sendingDomains)
            {
                var domainName = Str(d, "DomainName");
                JsonElement config = default;
                bool found = domainName != null && dkimByDomain.TryGetValue(domainName, out config);

                if (!found || NotTruthyProp(config, "Enabled"))
                {
                    failed.Add((
                        domainName ?? "",
                        found ? Cell(config, "Enabled") : "Not Configured",
                        found ? "DKIM disabled" : "No DKIM config found"));
                }
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: DKIM is enabled for all {sendingDomains.Count} sending domain(s).");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {sendingDomains.Count} domain(s) do not have DKIM properly enabled:\n\n");
            sb.Append("| Domain | DKIM Enabled | Status |\n");
            sb.Append("| :----- | :----------- | :----- |\n");
            foreach (var f in failed)
                sb.Append($"| {f.Domain} | {f.Enabled} | {f.Status} |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
