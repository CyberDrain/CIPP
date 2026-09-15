using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Password Rule Settings - Enable password protection on Windows Server Active Directory. Port of Invoke-CippTestEIDSCAPR02. Source: Settings.</summary>
    public sealed class EIDSCAPR02 : ICippTest
    {
        public string Id => "EIDSCAPR02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "EnableBannedPasswordCheckOnPremises");
            if (StrIn(value, "True"))
                return new CippTestResult(TestStatus.Passed, "Password protection is enabled for on-premises Active Directory");

            var result = $@"Password protection should be enabled for on-premises Active Directory to prevent weak passwords.

**Current Configuration:**
- EnableBannedPasswordCheckOnPremises: {value}

**Recommended Configuration:**
- EnableBannedPasswordCheckOnPremises: True";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
