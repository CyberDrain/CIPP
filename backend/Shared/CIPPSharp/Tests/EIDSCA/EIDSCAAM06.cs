using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - Show App Name. Port of Invoke-CippTestEIDSCAAM06. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM06 : ICippTest
    {
        public string Id => "EIDSCAAM06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "enabled", "featureSettings", "displayAppInformationRequiredState", "state"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator app information display is enabled.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator app information display is not enabled. Current state: {PathCell(config, "featureSettings", "displayAppInformationRequiredState", "state")}");
        }
    }
}
