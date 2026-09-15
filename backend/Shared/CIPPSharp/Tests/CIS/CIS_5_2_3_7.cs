using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.7) — The email OTP authentication method SHALL be disabled.
    /// Port of Invoke-CippTestCIS_5_2_3_7. An absent Email method counts as disabled.
    /// </summary>
    public sealed class CIS_5_2_3_7 : ICippTest
    {
        public string Id => "CIS_5_2_3_7";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var amp = data.Get("AuthenticationMethodsPolicy");
            if (!Any(amp))
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");

            var cfg = FirstOrNull(amp)!.Value;
            var email = FindInArray(Path(cfg, "authenticationMethodConfigurations"), "id", "Email");

            if (email == null || StrEq(email.Value, "state", "disabled"))
                return new CippTestResult(TestStatus.Passed, "Email OTP authentication method is disabled.");

            return new CippTestResult(TestStatus.Failed,
                $"Email OTP authentication method is enabled (state: {Str(email.Value, "state")}).");
        }
    }
}
