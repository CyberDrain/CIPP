using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authorization Policy - Self-Service Password Reset for Admins. Port of Invoke-CippTestEIDSCAAP01. Source: AuthorizationPolicy.</summary>
    public sealed class EIDSCAAP01 : ICippTest
    {
        public string Id => "EIDSCAAP01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthorizationPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (IsFalseAt(record, "allowedToUseSSPR"))
                return new CippTestResult(TestStatus.Passed, "Self-service password reset for administrators is disabled");

            var result = $@"Self-service password reset for administrators should be disabled for enhanced security.

**Current Configuration:**
- allowedToUseSSPR: {PathCell(record, "allowedToUseSSPR")}

**Recommended Configuration:**
- allowedToUseSSPR: false

Administrators should follow more stringent password reset procedures rather than self-service options.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
