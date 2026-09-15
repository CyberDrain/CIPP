using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>FIDO2 - Key Restrictions. Port of Invoke-CippTestEIDSCAAF04. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAF04 : ICippTest
    {
        public string Id => "EIDSCAAF04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var fido2 = FindMethodConfig(First(policy), "Fido2");
            if (!Found(fido2))
                return new CippTestResult(TestStatus.Failed, "FIDO2 configuration not found in Authentication Methods Policy.");

            if (PathIsTrue(fido2, "keyRestrictions", "isEnforced"))
                return new CippTestResult(TestStatus.Passed, "FIDO2 key restrictions are enforced");

            var result = $@"FIDO2 key restrictions should be enforced to control which security keys can be registered.

**Current Configuration:**
- keyRestrictions.isEnforced: {PathCell(fido2, "keyRestrictions", "isEnforced")}

**Recommended Configuration:**
- keyRestrictions.isEnforced: true

Enforcing key restrictions helps ensure only approved security keys are used in your organization.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
