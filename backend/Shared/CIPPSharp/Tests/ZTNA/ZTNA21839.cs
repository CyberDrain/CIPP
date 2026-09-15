using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Passkey authentication method enabled.
    /// Port of Invoke-CippTestZTNA21839. FIDO2 must be enabled and have include targets configured.
    /// </summary>
    public sealed class ZTNA21839 : ICippTest
    {
        private const string SkipMessage =
            "No data found in database. This may be due to missing required licenses or data collection not yet completed.";
        private const string PortalLink =
            "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods";

        public string Id => "ZTNA21839";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods)) return new CippTestResult(TestStatus.Skipped, SkipMessage);
            if (!ZTNA21838.TryFindFido2(authMethods, out var fido2)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            bool enabled = StrEq(fido2, "state", "enabled");
            bool hasIncludeTargets = ArrayLen(fido2, "includeTargets") > 0;

            var details = new StringBuilder($"\n## [Passkey authentication method details]({PortalLink})\n");
            details.Append($"- **Status** : {(enabled ? "Enabled ✅" : "Disabled ❌")}\n");
            if (enabled)
            {
                details.Append("- **Include targets** : ");
                var targets = new List<string>();
                foreach (var t in Arr(fido2, "includeTargets"))
                {
                    var id = Str(t, "id");
                    if (id == null) continue;
                    targets.Add(string.Equals(id, "all_users", System.StringComparison.OrdinalIgnoreCase) ? "All users" : id);
                }
                details.Append(targets.Count > 0 ? string.Join(", ", targets) + "\n" : "None\n");

                details.Append($"- **Enforce attestation** : {Cell(Prop(fido2, "isAttestationEnforced"))}\n");

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
                }
            }

            bool passed = enabled && hasIncludeTargets;
            string header = passed
                ? "Passkey authentication method is enabled and configured for users in your tenant."
                : "Passkey authentication method is not enabled or not configured for any users in your tenant.";

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, header + details.ToString());
        }
    }
}
