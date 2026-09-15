using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>FIDO2 - Specific Keys. Port of Invoke-CippTestEIDSCAAF06. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAF06 : ICippTest
    {
        public string Id => "EIDSCAAF06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var fido2 = FindMethodConfig(First(policy), "Fido2");
            if (!Found(fido2))
                return new CippTestResult(TestStatus.Failed, "FIDO2 configuration not found in Authentication Methods Policy.");

            var count = ArrCount(fido2, "keyRestrictions", "aaGuids");
            var enforcementType = PathStr(fido2, "keyRestrictions", "enforcementType");

            if (count > 0 && StrIn(enforcementType, "allow", "block"))
                return new CippTestResult(TestStatus.Passed,
                    $"FIDO2 key restrictions are properly configured with enforcement type '{enforcementType}' and {count} AAGuids");

            var result = $@"FIDO2 key restrictions should have both AAGuids configured and a valid enforcement type (allow or block).

**Current Configuration:**
- keyRestrictions.aaGuids: {count} GUIDs configured
- keyRestrictions.enforcementType: {enforcementType}

**Recommended Configuration:**
- keyRestrictions.aaGuids: One or more AAGuids
- keyRestrictions.enforcementType: 'allow' or 'block'

Proper enforcement type ensures the AAGuids list is actively used to control key registration.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
