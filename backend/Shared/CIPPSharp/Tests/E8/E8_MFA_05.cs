using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (MFA) — weak authentication methods (SMS / Voice / Email OTP) are disabled. Port of
    /// Invoke-CippTestE8_MFA_05. Single source: AuthenticationMethodsPolicy.
    /// </summary>
    public sealed class E8_MFA_05 : ICippTest
    {
        private static readonly string[] Weak = { "Sms", "Voice", "Email" };

        public string Id => "E8_MFA_05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!CippTestHelpers.Any(policy))
            {
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");
            }

            var configs = CippTestHelpers.Project(CippTestHelpers.Items(policy), "authenticationMethodConfigurations").ToList();
            var issues = new List<string>();
            foreach (var id in Weak)
            {
                if (configs.Any(c => CippTestHelpers.StrEq(c, "id", id) && CippTestHelpers.StrEq(c, "state", "enabled")))
                    issues.Add(id);
            }

            if (issues.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "SMS, Voice and Email OTP methods are all disabled.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"The following weak (non phishing-resistant) MFA methods are still enabled: {string.Join(", ", issues)}.");
        }
    }
}
