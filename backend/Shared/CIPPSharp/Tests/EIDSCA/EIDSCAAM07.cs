using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - Show App Name Target. Port of Invoke-CippTestEIDSCAAM07. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM07 : ICippTest
    {
        public string Id => "EIDSCAAM07";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "all_users", "featureSettings", "displayAppInformationRequiredState", "includeTarget", "id"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator app information display targets all users.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator app information display does not target all users. Current target: {PathCell(config, "featureSettings", "displayAppInformationRequiredState", "includeTarget", "id")}");
        }
    }
}
