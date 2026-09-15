using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>MS Authenticator - OTP Disabled. Port of Invoke-CippTestEIDSCAAM02. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAM02 : ICippTest
    {
        public string Id => "EIDSCAAM02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var config = FindMethodConfig(First(policy), "MicrosoftAuthenticator");
            // PS: $MethodConfig.isSoftwareOathEnabled -eq $false (missing → not false → Failed).
            if (IsFalseAt(config, "isSoftwareOathEnabled"))
                return new CippTestResult(TestStatus.Passed, "Microsoft Authenticator software OATH is disabled.");

            return new CippTestResult(TestStatus.Failed,
                "Microsoft Authenticator software OATH is enabled. It should be disabled.");
        }
    }
}
