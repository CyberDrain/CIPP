using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Consent Policy Settings - Block user consent for risky apps. Port of Invoke-CippTestEIDSCACP03. Source: Settings.</summary>
    public sealed class EIDSCACP03 : ICippTest
    {
        public string Id => "EIDSCACP03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "BlockUserConsentForRiskyApps");
            if (StrIn(value, "true"))
                return new CippTestResult(TestStatus.Passed, "User consent for risky apps is blocked");

            var result = $@"User consent for risky apps should be blocked to prevent security risks.

**Current Configuration:**
- BlockUserConsentForRiskyApps: {value}

**Recommended Configuration:**
- BlockUserConsentForRiskyApps: true";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
