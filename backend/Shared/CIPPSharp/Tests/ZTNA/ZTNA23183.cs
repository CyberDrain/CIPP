using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Service principals use safe redirect URIs.
    /// Port of Invoke-CippTestZTNA23183. Skipped on no ServicePrincipals data. Tenant-owned service
    /// principals (non-Microsoft, not managed identities) with unsafe reply URLs are flagged. Passed
    /// when none are unsafe.
    /// </summary>
    public sealed class ZTNA23183 : ICippTest
    {
        public string Id => "ZTNA23183";
        private const string MicrosoftOwnerId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a";

        private static readonly Regex PlainHttp = new(@"^http://(?!localhost(?:[:/]|$))", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex CloudApp = new(@"\.cloudapp\.(?:net|azure\.com)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex IpHost = new(@"^https?://(?:\d{1,3}\.){3}\d{1,3}", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var sps = data.Get("ServicePrincipals");
            if (!Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var tenantSps = new List<JsonElement>();
            foreach (var sp in Items(sps))
                if (!StrEq(sp, "appOwnerOrganizationId", MicrosoftOwnerId) && !StrEq(sp, "servicePrincipalType", "ManagedIdentity"))
                    tenantSps.Add(sp);

            // (spName, reason, uri)
            var failedRows = new List<(string Sp, string Reason, string Uri)>();
            int failedSps = 0;

            foreach (var sp in tenantSps)
            {
                var name = Text(sp, "displayName");
                var issues = new List<(string Reason, string Uri)>();
                foreach (var uri in FlattenStrings(sp, "replyUrls"))
                    foreach (var reason in TestUri(uri))
                        issues.Add((reason, uri));

                if (issues.Count > 0)
                {
                    failedSps++;
                    foreach (var iss in issues) failedRows.Add((name, iss.Reason, iss.Uri));
                }
            }

            if (failedSps == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {tenantSps.Count} tenant-owned service principal(s) use safe reply URLs.");

            var lines = new List<string>
            {
                $"{failedSps} of {tenantSps.Count} service principal(s) have unsafe reply URLs.",
                "",
                "| Service Principal | Issue | URI |",
                "| :---------------- | :---- | :-- |"
            };

            for (int i = 0; i < failedRows.Count && i < 50; i++)
            {
                var r = failedRows[i];
                lines.Add($"| {r.Sp} | {r.Reason} | {r.Uri} |");
            }

            lines.Add("");
            lines.Add("**Remediation:** Remove unsafe reply URLs from each affected service principal. Use only HTTPS URIs that you own with proper DNS — avoid wildcards, IPs, and shared Azure default domains.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }

        private static IEnumerable<string> TestUri(string? uri)
        {
            if (string.IsNullOrWhiteSpace(uri)) yield break;
            if (uri.Contains('*')) yield return "Wildcard URI";
            if (PlainHttp.IsMatch(uri)) yield return "Plain HTTP (non-localhost)";
            if (uri.IndexOf(".azurewebsites.net", StringComparison.OrdinalIgnoreCase) >= 0) yield return "Azure default *.azurewebsites.net domain";
            if (CloudApp.IsMatch(uri)) yield return "Azure default cloudapp domain";
            if (IpHost.IsMatch(uri)) yield return "IP-address redirect URI";
        }
    }
}
