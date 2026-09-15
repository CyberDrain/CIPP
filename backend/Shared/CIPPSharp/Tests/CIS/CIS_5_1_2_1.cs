using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.2.1) — 'Per-user MFA' SHALL be disabled. Port of Invoke-CippTestCIS_5_1_2_1.
    /// Single source: MFAState. Passed when no user still has legacy per-user MFA Enabled/Enforced.
    /// </summary>
    public sealed class CIS_5_1_2_1 : ICippTest
    {
        public string Id => "CIS_5_1_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mfa = data.Get("MFAState");
            if (!Any(mfa))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "MFAState cache not found. Please refresh the cache for this tenant.");
            }

            var enabled = new List<JsonElement>();
            foreach (var m in mfa.EnumerateArray())
            {
                if (InListCI(Str(m, "PerUserMFAState"), "Enabled", "Enforced")) enabled.Add(m);
            }

            if (enabled.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "No users have legacy per-user MFA enabled or enforced.");
            }

            var sb = new StringBuilder();
            sb.Append($"{enabled.Count} user(s) still have per-user MFA enabled or enforced — migrate them to Conditional Access:\n\n");
            var bullets = new List<string>();
            int shown = 0;
            foreach (var m in enabled)
            {
                if (shown++ >= 25) break;
                bullets.Add($"- {Str(m, "userPrincipalName")} ({Str(m, "PerUserMFAState")})");
            }
            sb.Append(string.Join("\n", bullets));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
