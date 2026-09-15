using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - State. Port of Invoke-CippTestEIDSCAAM01. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM01 : ICippTest
    {
        public string Id => "EIDSCAAM01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            if (PathStrEq(config, "enabled", "state"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator authentication method is enabled.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator authentication method is not enabled. Current state: {PathCell(config, "state")}");
        }
    }
}
