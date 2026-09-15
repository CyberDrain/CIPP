using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Security key attestation is enforced.
    /// Port of Invoke-CippTestZTNA21840. FIDO2 isAttestationEnforced must be true.
    /// </summary>
    public sealed class ZTNA21840 : ICippTest
    {
        private const string SkipMessage =
            "No data found in database. This may be due to missing required licenses or data collection not yet completed.";
        private const string PortalLink =
            "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods";

        public string Id => "ZTNA21840";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods)) return new CippTestResult(TestStatus.Skipped, SkipMessage);
            if (!ZTNA21838.TryFindFido2(authMethods, out var fido2)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            bool enforced = IsTrue(fido2, "isAttestationEnforced");

            var details = new StringBuilder($"\n## [Security key attestation policy details]({PortalLink})\n");
            details.Append($"- **Enforce attestation** : {(enforced ? "True ✅" : "False ❌")}\n");

            var keyRestrictions = Prop(fido2, "keyRestrictions");
            if (keyRestrictions.ValueKind != JsonValueKind.Undefined && keyRestrictions.ValueKind != JsonValueKind.Null)
            {
                details.Append("- **Key restriction policy** :\n");
                var isEnforced = Prop(keyRestrictions, "isEnforced");
                details.Append(isEnforced.ValueKind != JsonValueKind.Null && isEnforced.ValueKind != JsonValueKind.Undefined
                    ? $"  - **Enforce key restrictions** : {Cell(isEnforced)}\n"
                    : "  - **Enforce key restrictions** : Not configured\n");
                var enforcementType = Str(keyRestrictions, "enforcementType");
                details.Append(!string.IsNullOrEmpty(enforcementType)
                    ? $"  - **Restrict specific keys** : {enforcementType}\n"
                    : "  - **Restrict specific keys** : Not configured\n");

                if (ArrayLen(keyRestrictions, "aaGuids") > 0)
                {
                    details.Append("  - **AAGUID** :\n");
                    foreach (var g in Arr(keyRestrictions, "aaGuids"))
                        details.Append($"    - {Cell(g)}\n");
                }
            }

            string header = enforced
                ? "Security key attestation is properly enforced, ensuring only verified hardware authenticators can be registered."
                : "Security key attestation is not enforced, allowing unverified or potentially compromised security keys to be registered.";

            return new CippTestResult(enforced ? TestStatus.Passed : TestStatus.Failed, header + details.ToString());
        }
    }
}
