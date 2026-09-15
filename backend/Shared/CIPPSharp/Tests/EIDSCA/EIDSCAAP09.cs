using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Consent for Risky Apps. Port of Invoke-CippTestEIDSCAAP09. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP09 : ICippTest
    {
        public string Id => "EIDSCAAP09";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (IsFalseAt(record, "allowUserConsentForRiskyApps"))
                return new CippTestResult(TestStatus.Passed, "User consent for risky apps is disabled");

            var result = $@"User consent for risk-based apps should be disabled to prevent users from consenting to potentially malicious applications.

**Current Configuration:**
- allowUserConsentForRiskyApps: {PathCell(record, "allowUserConsentForRiskyApps")}

**Recommended Configuration:**
- allowUserConsentForRiskyApps: false

Disabling this prevents users from consenting to apps identified as risky.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
