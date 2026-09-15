using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// ORCA231 — anti-spam (hosted content filter) policy rule overlap. Rule-based (upstream ORCA /
    /// CIPP PR #587): no matching custom rule is fine (default anti-spam policy applies), so this
    /// reports only domains targeted by more than one enabled rule as Informational. Risk Medium.
    /// </summary>
    public sealed class ORCA231 : ICippTest
    {
        public string Id => "ORCA231";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            return OverlapResult(data.Get("ExoAcceptedDomains"), data.Get("ExoHostedContentFilterRule"), "Anti-spam");
        }
    }
}
