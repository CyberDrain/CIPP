using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Admin Consent - Enabled. Port of Invoke-CippTestEIDSCACR01. Source: AdminConsentRequestPolicy.</summary>
    public sealed class EIDSCACR01 : ICippTest
    {
        public string Id => "EIDSCACR01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AdminConsentRequestPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathIsTrue(record, "isEnabled"))
                return new CippTestResult(TestStatus.Passed, "Admin consent request workflow is enabled");

            var result = $@"Admin consent request workflow should be enabled to allow users to request administrator approval for applications.

**Current Configuration:**
- isEnabled: {PathCell(record, "isEnabled")}

**Recommended Configuration:**
- isEnabled: true

Enabling this workflow provides a secure process for users to request access to applications requiring admin consent.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
