using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.14) — Inbound anti-spam policies SHALL NOT contain allowed domains.
    /// Port of Invoke-CippTestCIS_2_1_14.
    /// </summary>
    public sealed class CIS_2_1_14 : ICippTest
    {
        public string Id => "CIS_2_1_14";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoHostedContentFilterPolicy");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var offending = new List<JsonElement>();
            int total = 0;
            foreach (var p in policies.EnumerateArray())
            {
                total++;
                if (CountGt0(p, "AllowedSenderDomains")) offending.Add(p);
            }

            if (offending.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {total} inbound anti-spam policy/policies have no allowed sender domains.");
            }

            var sb = new StringBuilder();
            sb.Append($"{offending.Count} inbound anti-spam policy/policies have allowed sender domains configured:\n\n");
            foreach (var p in offending)
            {
                var parts = new List<string>();
                foreach (var v in Arr(p, "AllowedSenderDomains")) parts.Add(Cell(v));
                sb.Append($"- **{Str(p, "Identity")}**: {string.Join(", ", parts)}\n");
            }
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
