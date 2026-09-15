using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// ORCA227 — each accepted domain is covered by a Safe Attachments policy. Rule-based (upstream
    /// ORCA / CIPP PR #587): a domain is covered only by an enabled ExoSafeAttachmentRules rule
    /// targeting it with no recipient/group/domain exclusions. DefenderForOffice365 licensing is gated
    /// upstream by the engine; this body only runs when licensed.
    /// </summary>
    public sealed class ORCA227 : ICippTest
    {
        public string Id => "ORCA227";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            if (!data.Has("ExoSafeAttachmentRules"))
                return new CippTestResult(TestStatus.Failed,
                    "No Safe Attachments rules found. Each domain should have a Safe Attachments policy.");

            return RuleCoverageResult(
                data.Get("ExoAcceptedDomains"), data.Get("ExoSafeAttachmentRules"),
                "Safe Attachments policies", "Safe Attachments policy", "Total Safe Attachments Rules");
        }
    }
}
