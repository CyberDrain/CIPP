using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// ORCA232 — anti-malware policy rule overlap. Rule-based (upstream ORCA / CIPP PR #587):
    /// no matching custom rule is fine (default anti-malware policy applies), so this reports only
    /// domains targeted by more than one enabled rule as Informational. Risk Medium.
    /// </summary>
    public sealed class ORCA232 : ICippTest
    {
        public string Id => "ORCA232";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            return OverlapResult(data.Get("ExoAcceptedDomains"), data.Get("ExoMalwareFilterRules"), "Anti-malware");
        }
    }
}
