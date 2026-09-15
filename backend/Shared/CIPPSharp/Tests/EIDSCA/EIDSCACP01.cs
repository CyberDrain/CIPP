using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Consent Policy Settings - Group owner consent for apps accessing data. Port of Invoke-CippTestEIDSCACP01. Source: Settings.</summary>
    public sealed class EIDSCACP01 : ICippTest
    {
        public string Id => "EIDSCACP01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "EnableGroupSpecificConsent");
            if (StrIn(value, "False"))
                return new CippTestResult(TestStatus.Passed, "Group owner consent for apps is disabled");

            var result = $@"Group owner consent should be disabled to prevent unauthorized app permissions.

**Current Configuration:**
- EnableGroupSpecificConsent: {value}

**Recommended Configuration:**
- EnableGroupSpecificConsent: False";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
