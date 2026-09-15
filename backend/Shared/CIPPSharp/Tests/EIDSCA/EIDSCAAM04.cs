using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - Number Matching Target. Port of Invoke-CippTestEIDSCAAM04. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM04 : ICippTest
    {
        public string Id => "EIDSCAAM04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "all_users", "featureSettings", "numberMatchingRequiredState", "includeTarget", "id"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator number matching targets all users.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator number matching does not target all users. Current target: {PathCell(config, "featureSettings", "numberMatchingRequiredState", "includeTarget", "id")}");
        }
    }
}
