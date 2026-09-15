using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Admin Consent - Notify Reviewers. Port of Invoke-CippTestEIDSCACR02. Source: AdminConsentRequestPolicy.</summary>
    public sealed class EIDSCACR02 : ICippTest
    {
        public string Id => "EIDSCACR02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AdminConsentRequestPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathIsTrue(record, "notifyReviewers"))
                return new CippTestResult(TestStatus.Passed, "Admin consent reviewers are notified of new requests");

            var result = $@"Admin consent reviewers should be notified when new consent requests are submitted.

**Current Configuration:**
- notifyReviewers: {PathCell(record, "notifyReviewers")}

**Recommended Configuration:**
- notifyReviewers: true

Enabling notifications ensures reviewers are promptly informed of pending consent requests.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
