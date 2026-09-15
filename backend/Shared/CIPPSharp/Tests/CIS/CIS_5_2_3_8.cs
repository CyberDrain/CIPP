using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.8) — Account 'Lockout threshold' SHALL be '10' or less.
    /// Port of Invoke-CippTestCIS_5_2_3_8. Absent Password Rule Settings → tenant default (10) applies → Passed.
    /// </summary>
    public sealed class CIS_5_2_3_8 : ICippTest
    {
        public string Id => "CIS_5_2_3_8";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings))
                return new CippTestResult(TestStatus.Skipped, "Settings cache not found.");

            var pwd = FindPasswordRuleSetting(settings);
            if (pwd == null)
                return new CippTestResult(TestStatus.Passed,
                    "Password Rule Settings not configured; the tenant default Lockout threshold of 10 applies, which is compliant (10 or less).");

            var n = IntOfString(SettingValue(pwd.Value, "LockoutThreshold"));
            if (n <= 10)
                return new CippTestResult(TestStatus.Passed,
                    $"Account Lockout threshold is set to {n}, which is 10 or less.");

            return new CippTestResult(TestStatus.Failed,
                $"Account Lockout threshold is set to {n}, which exceeds the maximum recommended value of 10.");
        }
    }
}
