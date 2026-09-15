using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Enhanced filtering on default (third-party) inbound connectors. Port of Invoke-CippTestORCA233_1.
    /// Single source: ExoInboundConnector. Only enabled connectors whose SenderDomains include the
    /// wildcard pattern <c>smtp:*;N</c> are relevant; each must skip the last IP (or list skip IPs),
    /// not be in test mode, and have no per-user scoping.
    /// </summary>
    public sealed class ORCA233_1 : ICippTest
    {
        public string Id => "ORCA233_1";

        // ^smtp:\*;(\d+)$ — case-insensitive (PS -match).
        private static readonly Regex WildcardPattern =
            new(@"^smtp:\*;\d+$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoInboundConnector"))
                return new CippTestResult(TestStatus.Passed,
                    "No inbound connectors are configured. Enhanced filtering is not required.");

            var relevant = new List<JsonElement>();
            foreach (var connector in Items(data.Get("ExoInboundConnector")))
            {
                if (!IsTrue(connector, "Enabled")) continue; // $_.Enabled -ne $true → skip
                if (StringValues(connector, "SenderDomains").Any(sd => WildcardPattern.IsMatch(sd)))
                    relevant.Add(connector);
            }

            if (relevant.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No enabled inbound connectors with wildcard sender domains were found. Enhanced filtering is not required.");

            var passed = new List<(string Identity, string Mode)>();
            var failed = new List<(string Identity, string Mode)>();
            foreach (var connector in relevant)
            {
                bool skipLast = IsTrue(connector, "EFSkipLastIP");
                int skipIpsCount = ArrayLen(connector, "EFSkipIPs");
                bool testMode = IsTrue(connector, "EFTestMode");
                int usersCount = ArrayLen(connector, "EFUsers");

                bool isCompliant = (skipLast || skipIpsCount > 0) && !testMode && usersCount == 0;

                string mode = skipLast ? "Last IP"
                    : skipIpsCount > 0 ? $"Skip IPs ({skipIpsCount})"
                    : "Not Configured";
                if (testMode) mode += " (Test Mode)";
                if (usersCount > 0) mode += $" (Select Users: {usersCount})";

                var entry = (Identity: Str(connector, "Identity") ?? "", Mode: mode);
                if (isCompliant) passed.Add(entry);
                else failed.Add(entry);
            }

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All inbound connectors with wildcard sender domains have enhanced filtering configured.\n\n");
                sb.Append($"**Compliant Connectors:** {passed.Count}\n\n");
                var rows = passed.Select(e => (IReadOnlyList<string>)new[] { e.Identity, e.Mode }).ToList();
                sb.Append(Markdown.Table(new[] { "Connector", "EF Mode" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} inbound connectors do not have enhanced filtering configured correctly.\n\n");
            f.Append($"**Failed:** {failed.Count} | **Passed:** {passed.Count}\n\n");
            var frows = failed.Select(e => (IReadOnlyList<string>)new[] { e.Identity, e.Mode }).ToList();
            f.Append(Markdown.Table(new[] { "Connector", "EF Mode" }, frows));
            f.Append("\n**Remediation:** Enable enhanced filtering on each connector by setting EFSkipLastIP = $true (or populating EFSkipIPs), with EFTestMode = $false and no per-user scoping.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
