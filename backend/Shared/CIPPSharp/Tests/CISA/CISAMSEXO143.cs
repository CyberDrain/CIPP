using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.14.3 — Spam filter bypass SHALL be disabled (no allowed senders/domains).
    /// Port of Invoke-CippTestCISAMSEXO143. A policy fails when it has any AllowedSenders or
    /// AllowedSenderDomains configured (PS: <c>if ($x) { $x.Count } else { 0 }</c> then <c>&gt; 0</c>).
    /// </summary>
    public sealed class CISAMSEXO143 : ICippTest
    {
        public string Id => "CISAMSEXO143";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoHostedContentFilterPolicy");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.");

            var failed = new List<(string Name, int Senders, int Domains)>();
            int total = 0;
            foreach (var p in Items(policies))
            {
                total++;
                int senders = CountOrZero(p, "AllowedSenders");
                int domains = CountOrZero(p, "AllowedSenderDomains");
                if (senders > 0 || domains > 0)
                    failed.Add((Cell(p, "Name"), senders, domains));
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} anti-spam policy/policies have no spam filter bypasses configured.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} anti-spam policy/policies have spam filter bypasses configured:\n\n");
            sb.Append("| Policy Name | Allowed Senders | Allowed Domains | Issue |\n");
            sb.Append("| :---------- | :-------------- | :-------------- | :---- |\n");
            foreach (var f in failed)
                sb.Append($"| {f.Name} | {f.Senders} | {f.Domains} | Has allowed senders/domains that bypass spam filtering |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
