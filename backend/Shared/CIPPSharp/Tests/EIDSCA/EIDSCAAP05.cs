using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Email-Based Subscription Sign-up. Port of Invoke-CippTestEIDSCAAP05. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP05 : ICippTest
    {
        public string Id => "EIDSCAAP05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (IsFalseAt(record, "allowedToSignUpEmailBasedSubscriptions"))
                return new CippTestResult(TestStatus.Passed, "Email-based subscription sign-up is disabled");

            var result = $@"Email-based subscription sign-up should be disabled to prevent unauthorized subscriptions.

**Current Configuration:**
- allowedToSignUpEmailBasedSubscriptions: {PathCell(record, "allowedToSignUpEmailBasedSubscriptions")}

**Recommended Configuration:**
- allowedToSignUpEmailBasedSubscriptions: false

Disabling email-based subscriptions helps maintain control over tenant access.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
