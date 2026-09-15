using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>FIDO2 - Restricted Keys. Port of Invoke-CippTestEIDSCAAF05. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAF05 : ICippTest
    {
        public string Id => "EIDSCAAF05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var fido2 = FindMethodConfig(First(policy), "Fido2");
            if (!Found(fido2))
                return new CippTestResult(TestStatus.Failed, "FIDO2 configuration not found in Authentication Methods Policy.");

            var count = ArrCount(fido2, "keyRestrictions", "aaGuids");
            if (count > 0)
                return new CippTestResult(TestStatus.Passed,
                    $"FIDO2 key restrictions have specific AAGuids configured ({count} GUIDs)");

            var result = @"FIDO2 key restrictions should specify AAGuids to control which authenticator models can be registered.

**Current Configuration:**
- keyRestrictions.aaGuids: Empty or not configured

**Recommended Configuration:**
- keyRestrictions.aaGuids: Should contain one or more AAGuids

Specifying AAGuids allows you to restrict registration to specific, approved security key models.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
