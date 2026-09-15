using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>FIDO2 - Self-Service. Port of Invoke-CippTestEIDSCAAF02. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAF02 : ICippTest
    {
        public string Id => "EIDSCAAF02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var fido2 = FindMethodConfig(First(policy), "Fido2");
            if (!Found(fido2))
                return new CippTestResult(TestStatus.Failed, "FIDO2 configuration not found in Authentication Methods Policy.");

            if (PathIsTrue(fido2, "isSelfServiceRegistrationAllowed"))
                return new CippTestResult(TestStatus.Passed, "FIDO2 self-service registration is enabled");

            var result = $@"FIDO2 self-service registration should be enabled to allow users to register their own security keys.

**Current Configuration:**
- isSelfServiceRegistrationAllowed: {PathCell(fido2, "isSelfServiceRegistrationAllowed")}

**Recommended Configuration:**
- isSelfServiceRegistrationAllowed: true

Enabling self-service registration improves user experience and adoption of FIDO2 security keys.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
