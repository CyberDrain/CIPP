using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Security key authentication method enabled.
    /// Port of Invoke-CippTestZTNA21838. The FIDO2 authentication method config must be enabled.
    /// </summary>
    public sealed class ZTNA21838 : ICippTest
    {
        private const string SkipMessage =
            "No data found in database. This may be due to missing required licenses or data collection not yet completed.";

        public string Id => "ZTNA21838";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            if (!TryFindFido2(authMethods, out var fido2)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            bool enabled = StrEq(fido2, "state", "enabled");
            string emoji = enabled ? "✅" : "❌";

            var sb = new StringBuilder(enabled
                ? "Security key authentication method is enabled for your tenant, providing hardware-backed phishing-resistant authentication.\n\n"
                : "Security key authentication method is not enabled; users cannot register FIDO2 security keys for strong authentication.\n\n");

            sb.Append("## FIDO2 security key authentication settings\n\n");
            sb.Append($"{emoji} **FIDO2 authentication method**\n");
            sb.Append($"- Status: {Text(fido2, "state")}\n");
            sb.Append($"- Include targets: {Targets(fido2, "includeTargets", true)}\n");
            sb.Append($"- Exclude targets: {Targets(fido2, "excludeTargets", false)}\n");

            return new CippTestResult(enabled ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        internal static bool TryFindFido2(JsonElement authMethods, out JsonElement fido2)
        {
            foreach (var rec in Items(authMethods))
                foreach (var m in Arr(rec, "authenticationMethodConfigurations"))
                    if (StrEq(m, "id", "Fido2")) { fido2 = m; return true; }
            fido2 = default;
            return false;
        }

        private static string Targets(JsonElement fido2, string name, bool mapAllUsers)
        {
            var parts = new List<string>();
            foreach (var t in Arr(fido2, name))
            {
                var id = Str(t, "id");
                if (id == null) continue;
                parts.Add(mapAllUsers && string.Equals(id, "all_users", System.StringComparison.OrdinalIgnoreCase) ? "All users" : id);
            }
            return parts.Count > 0 ? string.Join(", ", parts) : "None";
        }
    }
}
