using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>FIDO2 - State. Port of Invoke-CippTestEIDSCAAF01. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAF01 : ICippTest
    {
        public string Id => "EIDSCAAF01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var fido2 = FindMethodConfig(First(policy), "Fido2");
            if (!Found(fido2))
                return new CippTestResult(TestStatus.Failed, "FIDO2 configuration not found in Authentication Methods Policy.");

            if (PathStrEq(fido2, "enabled", "state"))
                return new CippTestResult(TestStatus.Passed, "FIDO2 authentication method is enabled");

            var result = $@"FIDO2 security keys should be enabled to provide strong, phishing-resistant authentication.

**Current Configuration:**
- State: {PathCell(fido2, "state")}

**Recommended Configuration:**
- State: enabled

Enabling FIDO2 provides users with a secure, passwordless authentication option.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
