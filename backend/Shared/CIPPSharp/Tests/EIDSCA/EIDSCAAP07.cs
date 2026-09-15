using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Guest User Access. Port of Invoke-CippTestEIDSCAAP07. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP07 : ICippTest
    {
        public string Id => "EIDSCAAP07";

        private const string ExpectedRoleId = "2af84b1e-32c8-42b7-82bc-daa82404023b";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathStrEq(record, ExpectedRoleId, "guestUserRoleId"))
                return new CippTestResult(TestStatus.Passed, "Guest user access is restricted (most restrictive)");

            var result = $@"Guest user access should be set to the most restrictive level for enhanced security.

**Current Configuration:**
- guestUserRoleId: {PathCell(record, "guestUserRoleId")}

**Recommended Configuration:**
- guestUserRoleId: {ExpectedRoleId} (Most restrictive guest permissions)

This setting limits what guest users can see and do in your directory.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
