using System;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.3) — Password protection SHALL be enabled for on-prem Active Directory.
    /// Port of Invoke-CippTestCIS_5_2_3_3. Cloud-only tenants pass (not applicable); synced tenants
    /// must have on-prem banned-password protection in Enforce mode.
    /// </summary>
    public sealed class CIS_5_2_3_3 : ICippTest
    {
        public string Id => "CIS_5_2_3_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            var org = data.Get("Organization");

            if (!Any(settings) || !Any(org))
                return new CippTestResult(TestStatus.Skipped, "Required cache (Settings or Organization) not found.");

            var orgCfg = FirstOrNull(org)!.Value;
            if (!IsTrue(orgCfg, "onPremisesSyncEnabled"))
                return new CippTestResult(TestStatus.Passed, "Tenant is cloud-only — recommendation does not apply.");

            var pwd = FindPasswordRuleSetting(settings);
            var enableForOnPrem = pwd.HasValue ? SettingValue(pwd.Value, "EnableBannedPasswordCheckOnPremises") : null;
            var mode = pwd.HasValue ? SettingValue(pwd.Value, "BannedPasswordCheckOnPremisesMode") : null;

            if (string.Equals(enableForOnPrem, "True", StringComparison.OrdinalIgnoreCase)
                && string.Equals(mode, "Enforce", StringComparison.OrdinalIgnoreCase))
            {
                return new CippTestResult(TestStatus.Passed, "On-prem password protection is enabled in Enforce mode.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"On-prem password protection is not in Enforce mode. EnableBannedPasswordCheckOnPremises: {enableForOnPrem}; Mode: {mode}.");
        }
    }
}
