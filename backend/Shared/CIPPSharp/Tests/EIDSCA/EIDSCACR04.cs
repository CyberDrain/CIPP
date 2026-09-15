using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Admin Consent - Duration. Port of Invoke-CippTestEIDSCACR04. Source: AdminConsentRequestPolicy.</summary>
    public sealed class EIDSCACR04 : ICippTest
    {
        public string Id => "EIDSCACR04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AdminConsentRequestPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            // PS: $RequestDuration -le 30 — a missing value coerces to 0 (0 -le 30 → Passed).
            if (NumAt(record, "requestDurationInDays") <= 30)
                return new CippTestResult(TestStatus.Passed,
                    $"Admin consent request duration is set to {PathCell(record, "requestDurationInDays")} days (30 days or less)");

            var result = $@"Admin consent request duration should be set to 30 days or less to ensure timely review.

**Current Configuration:**
- requestDurationInDays: {PathCell(record, "requestDurationInDays")}

**Recommended Configuration:**
- requestDurationInDays: 30 or less

A shorter duration ensures consent requests are reviewed and processed in a timely manner.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
