using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Reduce the user-visible password surface area.
    /// Port of Invoke-CippTestZTNA21889. Skipped on no AuthenticationMethodsPolicy data. Passed when
    /// both FIDO2 (enabled + targets) and Microsoft Authenticator (enabled + targets + a valid
    /// authentication mode of 'any' or 'deviceBasedPush') are configured.
    /// </summary>
    public sealed class ZTNA21889 : ICippTest
    {
        public string Id => "ZTNA21889";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("AuthenticationMethodsPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "Unable to retrieve authentication methods policy from cache.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            JsonElement fido2 = default, authenticator = default;
            foreach (var cfg in Arr(policy, "authenticationMethodConfigurations"))
            {
                if (StrEq(cfg, "id", "Fido2")) fido2 = cfg;
                if (StrEq(cfg, "id", "MicrosoftAuthenticator")) authenticator = cfg;
            }

            bool fido2Enabled = StrEq(fido2, "state", "enabled");
            bool fido2HasTargets = ArrayLen(fido2, "includeTargets") > 0;
            bool fido2Valid = fido2Enabled && fido2HasTargets;

            bool authEnabled = StrEq(authenticator, "state", "enabled");
            bool authHasTargets = ArrayLen(authenticator, "includeTargets") > 0;

            string? authMode = null;
            foreach (var target in Arr(authenticator, "includeTargets"))
            {
                var m = Str(target, "authenticationMode");
                if (!string.IsNullOrEmpty(m)) { authMode = m; break; }
            }

            bool authModeValid;
            if (string.IsNullOrEmpty(authMode))
            {
                authMode = "Not configured";
                authModeValid = false;
            }
            else
            {
                authModeValid = string.Equals(authMode, "any", System.StringComparison.OrdinalIgnoreCase)
                    || string.Equals(authMode, "deviceBasedPush", System.StringComparison.OrdinalIgnoreCase);
            }
            bool authValid = authEnabled && authHasTargets && authModeValid;

            bool passed = fido2Valid && authValid;

            var sb = new StringBuilder(passed
                ? "✅ **Pass**: Your organization has implemented multiple passwordless authentication methods reducing password exposure.\n\n"
                : "❌ **Fail**: Your organization relies heavily on password-based authentication, creating security vulnerabilities.\n\n");

            sb.Append("## Passwordless authentication methods\n\n");
            sb.Append("| Method | State | Include targets | Authentication mode | Status |\n");
            sb.Append("| :----- | :---- | :-------------- | :------------------ | :----- |\n");

            var fido2State = fido2Enabled ? "✅ Enabled" : "❌ Disabled";
            var fido2Targets = fido2HasTargets ? $"{ArrayLen(fido2, "includeTargets")} target(s)" : "None";
            var fido2Status = fido2Valid ? "✅ Pass" : "❌ Fail";
            sb.Append($"| FIDO2 Security Keys | {fido2State} | {fido2Targets} | N/A | {fido2Status} |\n");

            var authState = authEnabled ? "✅ Enabled" : "❌ Disabled";
            var authTargets = authHasTargets ? $"{ArrayLen(authenticator, "includeTargets")} target(s)" : "None";
            var authModeDisplay = authModeValid ? $"✅ {authMode}" : $"❌ {authMode}";
            var authStatus = authValid ? "✅ Pass" : "❌ Fail";
            sb.Append($"| Microsoft Authenticator | {authState} | {authTargets} | {authModeDisplay} | {authStatus} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
