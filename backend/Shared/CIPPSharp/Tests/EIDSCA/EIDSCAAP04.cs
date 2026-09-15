using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Guest Invite Restrictions. Port of Invoke-CippTestEIDSCAAP04. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP04 : ICippTest
    {
        public string Id => "EIDSCAAP04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            var allowInvitesFrom = PathStr(record, "allowInvitesFrom");
            if (StrIn(allowInvitesFrom, "adminsAndGuestInviters", "none"))
                return new CippTestResult(TestStatus.Passed,
                    $"Guest invite restrictions are properly configured: {allowInvitesFrom}");

            var result = $@"Guest invite restrictions should be set to limit who can invite guests for enhanced security.

**Current Configuration:**
- allowInvitesFrom: {PathCell(record, "allowInvitesFrom")}

**Recommended Configuration:**
- allowInvitesFrom: adminsAndGuestInviters OR none

Restricting guest invitations helps maintain control over external access to your tenant.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
