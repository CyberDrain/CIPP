using System;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.2) — Custom banned passwords lists SHALL be used.
    /// Port of Invoke-CippTestCIS_5_2_3_2. Reads the directory "Password Rule Settings" object and
    /// checks that EnableBannedPasswordCheck is on and a non-empty custom list is configured.
    /// </summary>
    public sealed class CIS_5_2_3_2 : ICippTest
    {
        public string Id => "CIS_5_2_3_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings))
                return new CippTestResult(TestStatus.Skipped, "Settings cache not found.");

            var pwd = FindPasswordRuleSetting(settings);
            if (pwd == null)
                return new CippTestResult(TestStatus.Failed,
                    "Password Rule Settings not found in directory settings — custom banned passwords have not been configured.");

            var enforce = SettingValue(pwd.Value, "EnableBannedPasswordCheck");
            var custom = SettingValue(pwd.Value, "BannedPasswordList");

            if (string.Equals(enforce, "True", StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(custom))
            {
                var words = custom!.Split('\t').Length;
                return new CippTestResult(TestStatus.Passed,
                    $"Custom banned passwords are enforced ({words} words).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Custom banned passwords not fully configured. EnableBannedPasswordCheck: {enforce}; BannedPasswordList length: {custom?.Length ?? 0}");
        }
    }
}
