using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Admin Consent - Reminders. Port of Invoke-CippTestEIDSCACR03. Source: AdminConsentRequestPolicy.</summary>
    public sealed class EIDSCACR03 : ICippTest
    {
        public string Id => "EIDSCACR03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AdminConsentRequestPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            if (PathIsTrue(record, "remindersEnabled"))
                return new CippTestResult(TestStatus.Passed, "Admin consent request reminders are enabled");

            var result = $@"Admin consent request reminders should be enabled to ensure timely review of pending requests.

**Current Configuration:**
- remindersEnabled: {PathCell(record, "remindersEnabled")}

**Recommended Configuration:**
- remindersEnabled: true

Enabling reminders helps prevent consent requests from being overlooked or delayed.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
