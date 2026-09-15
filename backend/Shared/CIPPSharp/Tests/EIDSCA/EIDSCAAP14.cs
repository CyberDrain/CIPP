using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Users Can Read Other Users. Port of Invoke-CippTestEIDSCAAP14. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP14 : ICippTest
    {
        public string Id => "EIDSCAAP14";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathIsTrue(record, "defaultUserRolePermissions", "allowedToReadOtherUsers"))
                return new CippTestResult(TestStatus.Passed, "Users can read other users (standard behavior for collaboration)");

            var result = $@"Users should be allowed to read other users' basic profile information for collaboration purposes.

**Current Configuration:**
- defaultUserRolePermissions.allowedToReadOtherUsers: {PathCell(record, "defaultUserRolePermissions", "allowedToReadOtherUsers")}

**Recommended Configuration:**
- defaultUserRolePermissions.allowedToReadOtherUsers: true

This setting enables basic collaboration features like Teams and SharePoint.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
