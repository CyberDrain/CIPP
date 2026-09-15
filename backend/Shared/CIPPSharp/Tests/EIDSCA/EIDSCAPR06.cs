using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Password Rule Settings - Lockout threshold. Port of Invoke-CippTestEIDSCAPR06. Source: Settings.</summary>
    public sealed class EIDSCAPR06 : ICippTest
    {
        public string Id => "EIDSCAPR06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "LockoutThreshold");
            // PS: [int]$SettingValue -le 10 (missing/empty → [int]$null = 0 → 0 -le 10 → Passed).
            if (SettingInt(value) <= 10)
                return new CippTestResult(TestStatus.Passed,
                    $"Lockout threshold is set to {value} failed attempts (maximum 10 attempts recommended)");

            var result = $@"Lockout threshold should be 10 or fewer failed attempts to protect against brute force attacks.

**Current Configuration:**
- LockoutThreshold: {value}

**Recommended Configuration:**
- LockoutThreshold: 10 or fewer";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
