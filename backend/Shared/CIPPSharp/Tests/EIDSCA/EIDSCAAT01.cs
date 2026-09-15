using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Temp Access Pass - State. Port of Invoke-CippTestEIDSCAAT01. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAT01 : ICippTest
    {
        public string Id => "EIDSCAAT01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var tap = FindMethodConfig(First(policy), "TemporaryAccessPass");
            if (!Found(tap))
                return new CippTestResult(TestStatus.Failed, "Temporary Access Pass configuration not found in Authentication Methods Policy.");

            if (PathStrEq(tap, "enabled", "state"))
                return new CippTestResult(TestStatus.Passed, "Temporary Access Pass is enabled");

            var result = $@"Temporary Access Pass should be enabled to facilitate secure onboarding of passwordless authentication methods.

**Current Configuration:**
- State: {PathCell(tap, "state")}

**Recommended Configuration:**
- State: enabled

Enabling TAP allows administrators to securely onboard users to passwordless authentication.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
