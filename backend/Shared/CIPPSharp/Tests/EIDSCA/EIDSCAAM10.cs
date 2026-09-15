using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - Show Location Target. Port of Invoke-CippTestEIDSCAAM10. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM10 : ICippTest
    {
        public string Id => "EIDSCAAM10";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "all_users", "featureSettings", "displayLocationInformationRequiredState", "includeTarget", "id"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator location information display targets all users.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator location information display does not target all users. Current target: {PathCell(config, "featureSettings", "displayLocationInformationRequiredState", "includeTarget", "id")}");
        }
    }
}
