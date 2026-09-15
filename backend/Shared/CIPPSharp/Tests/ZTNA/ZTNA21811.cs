using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Password expiration is disabled.
    /// Port of Invoke-CippTestZTNA21811. Root-level domains (subdomains inherit the root policy) whose
    /// passwordValidityPeriodInDays is set and not the "never expires" sentinel (2147483647) are
    /// misconfigured; users on such domains without DisablePasswordExpiration are also flagged.
    /// </summary>
    public sealed class ZTNA21811 : ICippTest
    {
        private const long NeverExpires = 2147483647;

        public string Id => "ZTNA21811";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var domains = data.Get("Domains");
            if (!Any(domains))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var domainList = new List<JsonElement>();
            foreach (var d in Items(domains)) domainList.Add(d);

            var domainIds = new List<string>();
            foreach (var d in domainList) { var id = Str(d, "id"); if (id != null) domainIds.Add(id); }

            // Subdomains: ids that are a suffix (".parent") of another id.
            var subDomains = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var id in domainIds)
                foreach (var parent in domainIds)
                    if (!string.Equals(id, parent, StringComparison.OrdinalIgnoreCase)
                        && id.EndsWith("." + parent, StringComparison.OrdinalIgnoreCase))
                    { subDomains.Add(id); break; }

            var misconfiguredDomains = new List<JsonElement>();
            foreach (var d in domainList)
            {
                var id = Str(d, "id");
                if (id != null && subDomains.Contains(id)) continue;
                if (TryValidity(d, out var days) && days != NeverExpires) misconfiguredDomains.Add(d);
            }

            var misconfiguredUsers = new List<(string DisplayName, string Upn, string PwPolicies, string DomainValidity)>();
            var users = data.Get("Users");
            if (Any(users))
            {
                foreach (var u in Items(users))
                {
                    var upn = Str(u, "userPrincipalName");
                    if (upn == null) continue;
                    var at = upn.LastIndexOf('@');
                    var userDomain = at >= 0 ? upn.Substring(at + 1) : upn;

                    JsonElement? matchedDomain = null;
                    foreach (var md in misconfiguredDomains)
                    {
                        var did = Str(md, "id");
                        if (did == null) continue;
                        if (string.Equals(userDomain, did, StringComparison.OrdinalIgnoreCase)
                            || userDomain.EndsWith("." + did, StringComparison.OrdinalIgnoreCase))
                        { matchedDomain = md; break; }
                    }

                    bool disablesExpiration = PropContains(u, "passwordPolicies", "DisablePasswordExpiration");
                    if (!disablesExpiration && matchedDomain.HasValue)
                    {
                        string dv = TryValidity(matchedDomain.Value, out var d2) ? d2.ToString() : "";
                        misconfiguredUsers.Add((Text(u, "displayName"), upn, Text(u, "passwordPolicies"), dv));
                    }
                }
            }

            bool failed = misconfiguredDomains.Count > 0 || misconfiguredUsers.Count > 0;
            var text = failed
                ? "Found domains or users with password expiration still enabled."
                : "Password expiration is properly disabled across all domains and users.";

            var sb = new StringBuilder(text);
            if (misconfiguredDomains.Count > 0)
            {
                sb.Append("\n## Domains with password expiration enabled\n\n");
                sb.Append("| Domain Name | Password Validity Interval |\n");
                sb.Append("| :---------- | :------------------------- |\n");
                foreach (var d in misconfiguredDomains)
                    sb.Append($"| {Text(d, "id")} | {Text(d, "passwordValidityPeriodInDays")} |\n");
            }
            if (misconfiguredUsers.Count > 0)
            {
                sb.Append("\n## Users with password expiration enabled\n\n");
                sb.Append("| Display Name | User Principal Name | User Password Expiration setting | Domain Password Expiration setting |\n");
                sb.Append("| :----------- | :------------------ | :------------------------------- | :--------------------------------- |\n");
                foreach (var u in misconfiguredUsers)
                    sb.Append($"| {u.DisplayName} | {u.Upn} | {u.PwPolicies} | {u.DomainValidity} |\n");
            }

            return new CippTestResult(failed ? TestStatus.Failed : TestStatus.Passed, sb.ToString());
        }

        // present, non-null, numeric (JSON number or numeric string).
        private static bool TryValidity(JsonElement domain, out long days)
        {
            days = 0;
            if (!TryProp(domain, "passwordValidityPeriodInDays", out var v)) return false;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out days)) return true;
            if (v.ValueKind == JsonValueKind.String && long.TryParse(v.GetString(), out days)) return true;
            return false;
        }
    }
}
