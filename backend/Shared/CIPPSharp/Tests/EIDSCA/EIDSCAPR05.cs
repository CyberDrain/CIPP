using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Password Rule Settings - Lockout duration in seconds. Port of Invoke-CippTestEIDSCAPR05. Source: Settings.</summary>
    public sealed class EIDSCAPR05 : ICippTest
    {
        public string Id => "EIDSCAPR05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "LockoutDurationInSeconds");
            // PS: [int]$SettingValue -ge 60 (missing/empty → [int]$null = 0 → Failed).
            if (SettingInt(value) >= 60)
                return new CippTestResult(TestStatus.Passed,
                    $"Lockout duration is set to {value} seconds (minimum 60 seconds required)");

            var result = $@"Lockout duration should be at least 60 seconds to protect against brute force attacks.

**Current Configuration:**
- LockoutDurationInSeconds: {value}

**Recommended Configuration:**
- LockoutDurationInSeconds: 60 or greater";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
