using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Users Can Create Apps. Port of Invoke-CippTestEIDSCAAP10. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP10 : ICippTest
    {
        public string Id => "EIDSCAAP10";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (IsFalseAt(record, "defaultUserRolePermissions", "allowedToCreateApps"))
                return new CippTestResult(TestStatus.Passed, "Users cannot create application registrations");

            var result = $@"Users should not be allowed to create application registrations by default to maintain control over applications.

**Current Configuration:**
- defaultUserRolePermissions.allowedToCreateApps: {PathCell(record, "defaultUserRolePermissions", "allowedToCreateApps")}

**Recommended Configuration:**
- defaultUserRolePermissions.allowedToCreateApps: false

Only authorized users should be able to register applications in your tenant.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
