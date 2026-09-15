using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - Show Location. Port of Invoke-CippTestEIDSCAAM09. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM09 : ICippTest
    {
        public string Id => "EIDSCAAM09";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "enabled", "featureSettings", "displayLocationInformationRequiredState", "state"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator location information display is enabled.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator location information display is not enabled. Current state: {PathCell(config, "featureSettings", "displayLocationInformationRequiredState", "state")}");
        }
    }
}
