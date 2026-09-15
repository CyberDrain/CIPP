using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>SMS - No Sign-In. Port of Invoke-CippTestEIDSCAAS04. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAS04 : ICippTest
    {
        public string Id => "EIDSCAAS04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var sms = FindMethodConfig(First(policy), "Sms");
            if (!Found(sms))
                return new CippTestResult(TestStatus.Failed, "SMS authentication configuration not found in Authentication Methods Policy.");

            // A target is invalid when isUsableForSignIn is NOT false (true, or missing).
            var invalid = 0;
            foreach (var target in Arr(sms, "includeTargets"))
            {
                if (!IsFalseAt(target, "isUsableForSignIn")) invalid++;
            }

            if (invalid == 0)
                return new CippTestResult(TestStatus.Passed, "SMS authentication is not allowed for sign-in on any targets");

            var result = $@"SMS should not be allowed for sign-in as it is vulnerable to SIM swap and interception attacks. SMS should only be used for MFA verification, not primary authentication.

**Current Configuration:**
- Targets with sign-in enabled: {invalid}

**Recommended Configuration:**
- All includeTargets should have isUsableForSignIn: false

Disabling SMS for sign-in while keeping it for MFA provides better security.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
