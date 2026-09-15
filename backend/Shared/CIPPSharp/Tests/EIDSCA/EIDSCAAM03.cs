using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - Number Matching. Port of Invoke-CippTestEIDSCAAM03. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM03 : ICippTest
    {
        public string Id => "EIDSCAAM03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "enabled", "featureSettings", "numberMatchingRequiredState", "state"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator number matching is enabled.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator number matching is not enabled. Current state: {PathCell(config, "featureSettings", "numberMatchingRequiredState", "state")}");
        }
    }
}
