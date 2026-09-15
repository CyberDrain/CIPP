using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authentication Methods - Suspicious Activity Target. Port of Invoke-CippTestEIDSCAAG03. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAG03 : ICippTest
    {
        public string Id => "EIDSCAAG03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathStrEq(record, "all_users", "reportSuspiciousActivitySettings", "includeTarget", "id"))
                return new CippTestResult(TestStatus.Passed, "Report suspicious activity is enabled for all users");

            var result = $@"Report suspicious activity should be enabled for all users.

**Current Configuration:**
- reportSuspiciousActivitySettings.includeTarget.id: {PathCell(record, "reportSuspiciousActivitySettings", "includeTarget", "id")}

**Recommended Configuration:**
- reportSuspiciousActivitySettings.includeTarget.id: all_users

All users should be able to report suspicious authentication attempts.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
