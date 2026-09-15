using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Consent Policy Settings - Users can request admin consent. Port of Invoke-CippTestEIDSCACP04. Source: Settings.</summary>
    public sealed class EIDSCACP04 : ICippTest
    {
        public string Id => "EIDSCACP04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "EnableAdminConsentRequests");
            if (StrIn(value, "true"))
                return new CippTestResult(TestStatus.Passed, "Users can request admin consent for apps");

            var result = $@"Users should be able to request admin consent to enable proper app approval workflows.

**Current Configuration:**
- EnableAdminConsentRequests: {value}

**Recommended Configuration:**
- EnableAdminConsentRequests: true";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
