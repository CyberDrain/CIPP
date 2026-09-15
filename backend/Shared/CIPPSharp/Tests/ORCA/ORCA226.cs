using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// ORCA226 — each accepted domain is covered by a Safe Links policy. Rule-based (upstream ORCA /
    /// CIPP PR #587): a domain is covered only by an enabled ExoSafeLinksRules rule targeting it with
    /// no recipient/group/domain exclusions. DefenderForOffice365 licensing is gated upstream by the
    /// engine (registry requiredCapabilities → Unlicensed); this body only runs when licensed.
    /// </summary>
    public sealed class ORCA226 : ICippTest
    {
        public string Id => "ORCA226";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            if (!data.Has("ExoSafeLinksRules"))
                return new CippTestResult(TestStatus.Failed,
                    "No Safe Links rules found. Each domain should have a Safe Links policy.");

            return RuleCoverageResult(
                data.Get("ExoAcceptedDomains"), data.Get("ExoSafeLinksRules"),
                "Safe Links policies", "Safe Links policy", "Total Safe Links Rules");
        }
    }
}
