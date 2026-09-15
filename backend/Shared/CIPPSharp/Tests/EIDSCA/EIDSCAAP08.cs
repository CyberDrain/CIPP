using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - User Consent Policy. Port of Invoke-CippTestEIDSCAAP08. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP08 : ICippTest
    {
        public string Id => "EIDSCAAP08";

        private const string ExpectedPolicy = "ManagePermissionGrantsForSelf.microsoft-user-default-low";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (ArrayContainsCI(record, "permissionGrantPolicyIdsAssignedToDefaultUserRole", ExpectedPolicy))
                return new CippTestResult(TestStatus.Passed, "User consent policy is set to low-risk permissions");

            var current = JoinArr(record, "permissionGrantPolicyIdsAssignedToDefaultUserRole", ", ");
            var result = $@"User consent policy should be configured to only allow consent for low-risk applications.

**Current Configuration:**
- permissionGrantPolicyIdsAssignedToDefaultUserRole: {current}

**Recommended Configuration:**
- permissionGrantPolicyIdsAssignedToDefaultUserRole: {ExpectedPolicy}

This limits users to only consent to applications with low-risk permissions.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
