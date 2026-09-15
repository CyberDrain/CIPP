using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.3.3) — 'External sharing' of calendars SHALL NOT be available.
    /// Port of Invoke-CippTestCIS_1_3_3. Inspects the default (or first) EXO sharing policy.
    /// </summary>
    public sealed class CIS_1_3_3 : ICippTest
    {
        public string Id => "CIS_1_3_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoSharingPolicy");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoSharingPolicy cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? def = null;
            foreach (var p in policies.EnumerateArray())
                if (IsTrue(p, "Default")) { def = p; break; }
            if (def == null) def = FirstOrNull(policies);

            var policy = def!.Value;
            var domains = new List<string>();
            foreach (var d in Arr(policy, "Domains"))
                if (d.ValueKind == JsonValueKind.String) domains.Add(d.GetString() ?? "");

            bool calendarSharing = false;
            foreach (var d in domains)
                if (MatchCI(d, "CalendarSharing")) { calendarSharing = true; break; }

            var name = Str(policy, "Name");
            bool enabled = IsTrue(policy, "Enabled");

            // Passed when there is no calendar-sharing domain OR the policy is disabled.
            if (!calendarSharing || IsFalse(policy, "Enabled"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Default sharing policy '{name}' does not allow external calendar sharing (Enabled: {BoolStr(enabled)}).");
            }

            var sb = new StringBuilder();
            sb.Append($"Default sharing policy '{name}' is enabled and allows external calendar sharing.\n\n**Domains entries:**\n");
            var lines = new List<string>();
            foreach (var d in domains) lines.Add($"- {d}");
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
