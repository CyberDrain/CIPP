using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Password Rule Settings - Password Protection Mode. Port of Invoke-CippTestEIDSCAPR01. Source: Settings.</summary>
    public sealed class EIDSCAPR01 : ICippTest
    {
        public string Id => "EIDSCAPR01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "BannedPasswordCheckOnPremisesMode");
            if (StrIn(value, "Enforce"))
                return new CippTestResult(TestStatus.Passed, "Password protection mode is set to Enforce");

            var result = $@"Password protection mode should be set to Enforce to prevent weak passwords.

**Current Configuration:**
- BannedPasswordCheckOnPremisesMode: {value}

**Recommended Configuration:**
- BannedPasswordCheckOnPremisesMode: Enforce";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
