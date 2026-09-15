using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (3.2.1) — DLP policies SHALL be enabled. Port of Invoke-CippTestCIS_3_2_1.
    /// Single source: DlpCompliancePolicies. Passed when at least one policy is in Enforce mode.
    /// </summary>
    public sealed class CIS_3_2_1 : ICippTest
    {
        public string Id => "CIS_3_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var dlp = data.Get("DlpCompliancePolicies");
            if (!Any(dlp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DlpCompliancePolicies cache not found. Please refresh the cache for this tenant.");
            }

            var enabled = new List<JsonElement>();
            int total = 0;
            foreach (var p in dlp.EnumerateArray())
            {
                total++;
                if (StrEq(p, "Mode", "Enable") && BoolEq(p, "Enabled", true)) enabled.Add(p);
            }

            if (enabled.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{enabled.Count} of {total} DLP policy/policies are enabled and in Enforce mode:\n\n");
                var bullets = new List<string>();
                foreach (var p in enabled) bullets.Add($"- {Str(p, "Name")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                $"No DLP policies are enabled in Enforce mode. {total} policy/policies exist but are in test/disabled state.");
        }
    }
}
