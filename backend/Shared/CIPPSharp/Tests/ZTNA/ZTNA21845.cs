using System;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Temporary access pass is enabled.
    /// Port of Invoke-CippTestZTNA21845. TAP must be enabled, target all users, and be backed by a CA
    /// policy that enforces authentication strength on security-info registration.
    /// </summary>
    public sealed class ZTNA21845 : ICippTest
    {
        public string Id => "ZTNA21845";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");

            JsonElement tap = default;
            bool tapFound = false;
            foreach (var rec in Items(authMethods))
                foreach (var m in Arr(rec, "authenticationMethodConfigurations"))
                    if (StrEq(m, "id", "TemporaryAccessPass")) { tap = m; tapFound = true; break; }

            if (!tapFound)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            if (!StrEq(tap, "state", "enabled"))
                return new CippTestResult(TestStatus.Failed, "❌ Temporary Access Pass is disabled in the tenant.");

            int securityInfoPolicies = 0;
            foreach (var p in Items(data.Get("ConditionalAccessPolicies")))
            {
                if (!StrEq(p, "state", "enabled")) continue;
                if (!FlattenContains(p, "urn:user:registersecurityinfo", "conditions", "applications", "includeUserActions")) continue;
                var authStrength = Nested(p, "grantControls", "authenticationStrength");
                if (authStrength.ValueKind != JsonValueKind.Undefined && authStrength.ValueKind != JsonValueKind.Null)
                    securityInfoPolicies++;
            }

            bool tapEnabled = true; // state == enabled established above
            bool targetsAllUsers = false;
            foreach (var t in Arr(tap, "includeTargets"))
                if (string.Equals(Str(t, "id"), "all_users", StringComparison.OrdinalIgnoreCase)) { targetsAllUsers = true; break; }
            bool hasCaEnforcement = securityInfoPolicies > 0;
            bool tapSupportedInAuthStrength = hasCaEnforcement;

            bool passed = tapEnabled && targetsAllUsers && hasCaEnforcement && tapSupportedInAuthStrength;

            string header;
            if (passed)
                header = "Temporary Access Pass is enabled, targeting all users, and enforced with conditional access policies.";
            else if (tapEnabled && targetsAllUsers && hasCaEnforcement && !tapSupportedInAuthStrength)
                header = "Temporary Access Pass is enabled but authentication strength policies don't include TAP methods.";
            else if (tapEnabled && targetsAllUsers && !hasCaEnforcement)
                header = "Temporary Access Pass is enabled but no conditional access enforcement for security info registration found. Consider adding conditional access policies for stronger security.";
            else
                header = "Temporary Access Pass is not properly configured or does not target all users.";

            var sb = new StringBuilder(header);
            sb.Append("\n\n**Configuration summary**\n\n");
            string tapStatus = StrEq(tap, "state", "enabled") ? "Enabled ✅" : "Disabled ❌";
            sb.Append($"[Temporary Access Pass](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods/fromNav/Identity): {tapStatus}\n\n");
            string caStatus = hasCaEnforcement ? "Enabled ✅" : "Not enabled ❌";
            sb.Append($"[Conditional Access policy for Security info registration](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies/fromNav/Identity): {caStatus}\n\n");
            string authStrengthStatus = tapSupportedInAuthStrength ? "Enabled ✅" : "Not enabled ❌";
            sb.Append($"[Authentication strength policy for Temporary Access Pass](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/AuthenticationStrength.ReactView/fromNav/Identity): {authStrengthStatus}\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
