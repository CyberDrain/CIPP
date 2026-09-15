using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Voice Call - Disabled. Port of Invoke-CippTestEIDSCAAV01. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAV01 : ICippTest
    {
        public string Id => "EIDSCAAV01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var voice = FindMethodConfig(First(policy), "Voice");
            if (!Found(voice))
                return new CippTestResult(TestStatus.Failed, "Voice authentication configuration not found in Authentication Methods Policy.");

            if (PathStrEq(voice, "disabled", "state"))
                return new CippTestResult(TestStatus.Passed, "Voice call authentication is disabled");

            var result = $@"Voice call authentication should be disabled as it is susceptible to social engineering and SIM swap attacks.

**Current Configuration:**
- State: {PathCell(voice, "state")}

**Recommended Configuration:**
- State: disabled

Disabling voice calls reduces the attack surface by eliminating a less secure authentication method.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
