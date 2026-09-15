using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>FIDO2 - Attestation. Port of Invoke-CippTestEIDSCAAF03. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAF03 : ICippTest
    {
        public string Id => "EIDSCAAF03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var fido2 = FindMethodConfig(First(policy), "Fido2");
            if (!Found(fido2))
                return new CippTestResult(TestStatus.Failed, "FIDO2 configuration not found in Authentication Methods Policy.");

            if (PathIsTrue(fido2, "isAttestationEnforced"))
                return new CippTestResult(TestStatus.Passed, "FIDO2 attestation enforcement is enabled");

            var result = $@"FIDO2 attestation should be enforced to verify the authenticity and security of FIDO2 security keys.

**Current Configuration:**
- isAttestationEnforced: {PathCell(fido2, "isAttestationEnforced")}

**Recommended Configuration:**
- isAttestationEnforced: true

Enforcing attestation ensures that only trusted and verified security keys can be registered.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
