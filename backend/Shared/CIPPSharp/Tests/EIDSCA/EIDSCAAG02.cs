using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authentication Methods - Report Suspicious Activity. Port of Invoke-CippTestEIDSCAAG02. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAG02 : ICippTest
    {
        public string Id => "EIDSCAAG02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathStrEq(record, "enabled", "reportSuspiciousActivitySettings", "state"))
                return new CippTestResult(TestStatus.Passed, "Report suspicious activity is enabled");

            var result = $@"Report suspicious activity should be enabled to allow users to report fraudulent MFA attempts.

**Current Configuration:**
- reportSuspiciousActivitySettings.state: {PathCell(record, "reportSuspiciousActivitySettings", "state")}

**Recommended Configuration:**
- reportSuspiciousActivitySettings.state: enabled

This feature helps detect and prevent unauthorized access attempts.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
