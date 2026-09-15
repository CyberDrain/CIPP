using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Password Rule Settings - Enforce custom list. Port of Invoke-CippTestEIDSCAPR03. Source: Settings.</summary>
    public sealed class EIDSCAPR03 : ICippTest
    {
        public string Id => "EIDSCAPR03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "EnableBannedPasswordCheck");
            if (StrIn(value, "True"))
                return new CippTestResult(TestStatus.Passed, "Custom banned password list is enforced");

            var result = $@"Custom banned password list should be enforced to prevent common weak passwords.

**Current Configuration:**
- EnableBannedPasswordCheck: {value}

**Recommended Configuration:**
- EnableBannedPasswordCheck: True";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
