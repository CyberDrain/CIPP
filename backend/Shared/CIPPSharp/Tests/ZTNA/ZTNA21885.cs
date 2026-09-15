using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// App registrations use safe redirect URIs.
    /// Port of Invoke-CippTestZTNA21885. Skipped on no Apps data. Each web/spa/publicClient redirect
    /// URI is checked for wildcards, plain HTTP (non-localhost), Azure default domains, and IP hosts.
    /// Passed when no application has an unsafe URI.
    /// </summary>
    public sealed class ZTNA21885 : ICippTest
    {
        public string Id => "ZTNA21885";

        private static readonly Regex PlainHttp = new(@"^http://(?!localhost(?:[:/]|$))", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex CloudApp = new(@"\.cloudapp\.(?:net|azure\.com)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
        private static readonly Regex IpHost = new(@"^https?://(?:\d{1,3}\.){3}\d{1,3}", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var apps = data.Get("Apps");
            if (!Any(apps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int inspected = 0;
            // (appName, section, reason, uri)
            var failedRows = new List<(string App, string Section, string Reason, string Uri)>();
            int failedApps = 0;

            foreach (var app in Items(apps))
            {
                inspected++;
                var appName = Text(app, "displayName");
                var issues = new List<(string Section, string Reason, string Uri)>();

                foreach (var uri in FlattenStrings(app, "web", "redirectUris")) TestUri(uri, "web", issues);
                foreach (var uri in FlattenStrings(app, "spa", "redirectUris")) TestUri(uri, "spa", issues);
                foreach (var uri in FlattenStrings(app, "publicClient", "redirectUris"))
                {
                    if (string.IsNullOrWhiteSpace(uri)) continue;
                    if (uri.Contains('*')) issues.Add(("publicClient", "Wildcard URI", uri));
                    if (uri.IndexOf(".azurewebsites.net", StringComparison.OrdinalIgnoreCase) >= 0)
                        issues.Add(("publicClient", "Azure default domain", uri));
                }

                if (issues.Count > 0)
                {
                    failedApps++;
                    foreach (var iss in issues) failedRows.Add((appName, iss.Section, iss.Reason, iss.Uri));
                }
            }

            if (failedApps == 0)
                return new CippTestResult(TestStatus.Passed, $"All {inspected} application(s) use safe redirect URIs.");

            var lines = new List<string>
            {
                $"{failedApps} of {inspected} application(s) have unsafe redirect URIs.",
                "",
                "| App | Section | Issue | URI |",
                "| :-- | :------ | :---- | :-- |"
            };

            for (int i = 0; i < failedRows.Count && i < 50; i++)
            {
                var r = failedRows[i];
                lines.Add($"| {r.App} | {r.Section} | {r.Reason} | {r.Uri} |");
            }

            lines.Add("");
            lines.Add("**Remediation:** Use only HTTPS URIs that you own and that have proper DNS. Avoid wildcards, IP addresses, and shared Azure default domains (*.azurewebsites.net, *.cloudapp.net) which are vulnerable to subdomain takeover.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }

        private static void TestUri(string? uri, string section, List<(string, string, string)> issues)
        {
            if (string.IsNullOrWhiteSpace(uri)) return;
            if (uri.Contains('*')) issues.Add((section, "Wildcard URI", uri));
            if (PlainHttp.IsMatch(uri)) issues.Add((section, "Plain HTTP (non-localhost)", uri));
            if (uri.IndexOf(".azurewebsites.net", StringComparison.OrdinalIgnoreCase) >= 0)
                issues.Add((section, "Azure default *.azurewebsites.net domain (subject to subdomain takeover)", uri));
            if (CloudApp.IsMatch(uri)) issues.Add((section, "Azure default cloudapp domain", uri));
            if (IpHost.IsMatch(uri)) issues.Add((section, "IP-address redirect URI", uri));
        }
    }
}
