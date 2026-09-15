using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Temp Access Pass - One-Time. Port of Invoke-CippTestEIDSCAAT02. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAT02 : ICippTest
    {
        public string Id => "EIDSCAAT02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var tap = FindMethodConfig(First(policy), "TemporaryAccessPass");
            if (!Found(tap))
                return new CippTestResult(TestStatus.Failed, "Temporary Access Pass configuration not found in Authentication Methods Policy.");

            if (PathIsTrue(tap, "isUsableOnce"))
                return new CippTestResult(TestStatus.Passed, "Temporary Access Pass is configured for one-time use");

            var result = $@"Temporary Access Pass should be configured for one-time use to minimize security risks.

**Current Configuration:**
- isUsableOnce: {PathCell(tap, "isUsableOnce")}

**Recommended Configuration:**
- isUsableOnce: true

One-time use reduces the risk of TAP credential theft or misuse.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
