using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Email Validation Join. Port of Invoke-CippTestEIDSCAAP06. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP06 : ICippTest
    {
        public string Id => "EIDSCAAP06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (IsFalseAt(record, "allowEmailVerifiedUsersToJoinOrganization"))
                return new CippTestResult(TestStatus.Passed, "Users cannot join the tenant by email validation");

            var result = $@"Email-validated users should not be allowed to join the organization to prevent unauthorized access.

**Current Configuration:**
- allowEmailVerifiedUsersToJoinOrganization: {PathCell(record, "allowEmailVerifiedUsersToJoinOrganization")}

**Recommended Configuration:**
- allowEmailVerifiedUsersToJoinOrganization: false

Disabling this feature prevents unauthorized users from self-registering into your tenant.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
