using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.9) — Account 'Lockout duration in seconds' SHALL be at least 60 seconds.
    /// Port of Invoke-CippTestCIS_5_2_3_9. Absent Password Rule Settings → tenant default (60) applies → Passed.
    /// </summary>
    public sealed class CIS_5_2_3_9 : ICippTest
    {
        public string Id => "CIS_5_2_3_9";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings))
                return new CippTestResult(TestStatus.Skipped, "Settings cache not found.");

            var pwd = FindPasswordRuleSetting(settings);
            if (pwd == null)
                return new CippTestResult(TestStatus.Passed,
                    "Password Rule Settings not configured; the tenant default Lockout duration of 60 seconds applies, which is compliant (at least 60 seconds).");

            var n = IntOfString(SettingValue(pwd.Value, "LockoutDurationInSeconds"));
            if (n >= 60)
                return new CippTestResult(TestStatus.Passed,
                    $"Account Lockout duration is set to {n} seconds, which is at least 60 seconds.");

            return new CippTestResult(TestStatus.Failed,
                $"Account Lockout duration is set to {n} seconds, which is less than the minimum recommended value of 60 seconds.");
        }
    }
}
