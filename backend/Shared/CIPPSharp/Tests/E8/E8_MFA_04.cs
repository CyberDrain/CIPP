using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (MFA) — at least one phishing-resistant authentication method is enabled. Port of
    /// Invoke-CippTestE8_MFA_04. Single source: AuthenticationMethodsPolicy. Checks FIDO2 and
    /// X509 certificate method configurations (Windows Hello for Business is not evaluable here).
    /// </summary>
    public sealed class E8_MFA_04 : ICippTest
    {
        private static readonly string[] Targets = { "Fido2", "X509Certificate" };

        public string Id => "E8_MFA_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!CippTestHelpers.Any(policy))
            {
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");
            }

            var configs = CippTestHelpers.Project(CippTestHelpers.Items(policy), "authenticationMethodConfigurations").ToList();
            var enabled = new List<string>();
            foreach (var id in Targets)
            {
                if (configs.Any(c => CippTestHelpers.StrEq(c, "id", id) && CippTestHelpers.StrEq(c, "state", "enabled")))
                    enabled.Add(id);
            }

            if (enabled.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Phishing-resistant authentication method(s) enabled: {string.Join(", ", enabled)}.");
            }

            return new CippTestResult(TestStatus.Failed,
                "No phishing-resistant authentication method (FIDO2 security key or X509 certificate-based auth) is enabled in the tenant. Windows Hello for Business is managed via Intune and is not evaluated by this test.");
        }
    }
}
