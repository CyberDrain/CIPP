using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// ORCA230 — anti-phishing policy rule overlap. Rule-based (upstream ORCA / CIPP PR #587):
    /// a domain with no matching custom rule is fine (the default anti-phish policy applies), so this
    /// only reports domains targeted by more than one enabled rule as Informational (only the
    /// lowest-priority rule actually applies). Risk Medium; no license gate.
    /// </summary>
    public sealed class ORCA230 : ICippTest
    {
        public string Id => "ORCA230";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            return OverlapResult(data.Get("ExoAcceptedDomains"), data.Get("ExoAntiPhishRules"), "Anti-phishing");
        }
    }
}
