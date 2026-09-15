using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.10) — Microsoft Authenticator on companion applications SHALL be disabled.
    /// Port of Invoke-CippTestCIS_5_2_3_10. Authenticator disabled entirely also satisfies the control.
    /// </summary>
    public sealed class CIS_5_2_3_10 : ICippTest
    {
        public string Id => "CIS_5_2_3_10";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var amp = data.Get("AuthenticationMethodsPolicy");
            if (!Any(amp))
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");

            var cfg = FirstOrNull(amp)!.Value;
            var auth = FindInArray(Path(cfg, "authenticationMethodConfigurations"), "id", "MicrosoftAuthenticator");

            if (auth == null)
                return new CippTestResult(TestStatus.Failed,
                    "MicrosoftAuthenticator authentication method configuration not found.");

            var a = auth.Value;
            var companionState = LeafStr(Path(a, "featureSettings", "companionAppAllowedState", "state"));

            if (StrEq(a, "state", "disabled"))
                return new CippTestResult(TestStatus.Passed,
                    "Microsoft Authenticator is disabled, so companion applications (Authenticator Lite) cannot be used.");

            if (LeafEqCI(Path(a, "featureSettings", "companionAppAllowedState", "state"), "disabled"))
                return new CippTestResult(TestStatus.Passed,
                    "Microsoft Authenticator on companion applications is disabled.");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator on companion applications is not disabled. Current companionAppAllowedState: {companionState}");
        }
    }
}
