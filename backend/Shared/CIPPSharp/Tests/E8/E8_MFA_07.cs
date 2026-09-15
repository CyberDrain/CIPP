using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (MFA) — all privileged users have a phishing-resistant authentication method
    /// registered. Port of Invoke-CippTestE8_MFA_07. Joins privileged Roles + PIM assignments +
    /// UserRegistrationDetails. Only privileged users that have a registration record are graded
    /// (matching the PS loop over the registration set).
    /// </summary>
    public sealed class E8_MFA_07 : ICippTest
    {
        private static readonly HashSet<string> PhishMethods = new(StringComparer.OrdinalIgnoreCase)
        {
            "fido2SecurityKey", "windowsHelloForBusiness", "x509CertificateSingleFactor",
            "x509CertificateMultiFactor", "passKeyDeviceBound", "passKeyDeviceBoundAuthenticator",
            "passKeyDeviceBoundWindowsHello"
        };

        public string Id => "E8_MFA_07";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var reg = data.Get("UserRegistrationDetails");
            var privRoles = CippTestHelpers.PrivilegedRoles(data);
            if (!CippTestHelpers.Any(reg) || privRoles.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (UserRegistrationDetails or Roles) not found.");
            }

            var privUserIds = CippTestHelpers.PrivilegedUserIds(privRoles, data, userMembersOnly: true);
            if (privUserIds.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "No privileged users found.");
            }

            var nonCompliant = new List<JsonElement>();
            foreach (var r in CippTestHelpers.Items(reg))
            {
                if (!privUserIds.Contains(CippTestHelpers.Str(r, "id") ?? "")) continue;
                if (!HasPhish(r)) nonCompliant.Add(r);
            }

            if (nonCompliant.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {privUserIds.Count} privileged users have at least one phishing-resistant method registered.");
            }

            var sb = new StringBuilder();
            sb.Append($"{nonCompliant.Count} of {privUserIds.Count} privileged users have no phishing-resistant method registered:\n\n");
            var rows = nonCompliant.Take(50).Select(r => (IReadOnlyList<string>)new[]
            {
                CippTestHelpers.Str(r, "userPrincipalName") ?? "", MethodsJoined(r)
            });
            sb.Append(Markdown.Table(new[] { "UPN", "Methods Registered" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        private static bool HasPhish(JsonElement reg)
        {
            foreach (var m in CippTestHelpers.Arr(reg, "methodsRegistered"))
            {
                if (m.ValueKind == JsonValueKind.String && PhishMethods.Contains(m.GetString() ?? "")) return true;
            }
            return false;
        }

        private static string MethodsJoined(JsonElement reg)
            => string.Join(", ", CippTestHelpers.Arr(reg, "methodsRegistered")
                .Select(m => m.ValueKind == JsonValueKind.String ? m.GetString() ?? "" : m.GetRawText()));
    }
}
