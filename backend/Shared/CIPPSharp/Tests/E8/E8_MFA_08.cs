using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (MFA) — all member users have a phishing-resistant authentication method registered.
    /// Port of Invoke-CippTestE8_MFA_08. Joins Users (enabled non-guest member ids) with
    /// UserRegistrationDetails; only members that have a registration record are graded.
    /// </summary>
    public sealed class E8_MFA_08 : ICippTest
    {
        private static readonly HashSet<string> PhishMethods = new(StringComparer.OrdinalIgnoreCase)
        {
            "fido2SecurityKey", "windowsHelloForBusiness", "x509CertificateSingleFactor",
            "x509CertificateMultiFactor", "passKeyDeviceBound", "passKeyDeviceBoundAuthenticator",
            "passKeyDeviceBoundWindowsHello"
        };

        public string Id => "E8_MFA_08";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var reg = data.Get("UserRegistrationDetails");
            var users = data.Get("Users");
            if (!CippTestHelpers.Any(reg) || !CippTestHelpers.Any(users))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (UserRegistrationDetails or Users) not found.");
            }

            var memberIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var u in CippTestHelpers.Items(users))
            {
                if (!CippTestHelpers.IsTrue(u, "accountEnabled") || CippTestHelpers.StrEq(u, "userType", "Guest")) continue;
                var id = CippTestHelpers.Str(u, "id");
                if (!string.IsNullOrEmpty(id)) memberIds.Add(id!);
            }

            if (memberIds.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "No enabled member users found.");
            }

            int total = 0, nonCompliant = 0;
            foreach (var r in CippTestHelpers.Items(reg))
            {
                if (!memberIds.Contains(CippTestHelpers.Str(r, "id") ?? "")) continue;
                total++;
                if (!HasPhish(r)) nonCompliant++;
            }

            if (nonCompliant == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {total} enabled member users have a phishing-resistant method registered.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"{nonCompliant} of {total} enabled member users have no phishing-resistant authentication method registered (FIDO2, Windows Hello for Business, X509 cert, or device-bound passkey).");
        }

        private static bool HasPhish(JsonElement reg)
        {
            foreach (var m in CippTestHelpers.Arr(reg, "methodsRegistered"))
            {
                if (m.ValueKind == JsonValueKind.String && PhishMethods.Contains(m.GetString() ?? "")) return true;
            }
            return false;
        }
    }
}
