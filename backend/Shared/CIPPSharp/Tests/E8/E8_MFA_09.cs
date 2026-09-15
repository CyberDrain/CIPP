using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (MFA) — Microsoft Authenticator number matching is enforced. Port of
    /// Invoke-CippTestE8_MFA_09. Single source: AuthenticationMethodsPolicy. When the Microsoft
    /// Authenticator method is not enabled the check passes (nothing to enforce).
    /// </summary>
    public sealed class E8_MFA_09 : ICippTest
    {
        public string Id => "E8_MFA_09";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!CippTestHelpers.Any(policy))
            {
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");
            }

            var configs = CippTestHelpers.Project(CippTestHelpers.Items(policy), "authenticationMethodConfigurations").ToList();
            var msAuth = configs.Where(c => CippTestHelpers.StrEq(c, "id", "MicrosoftAuthenticator")).ToList();
            if (msAuth.Count == 0 || !msAuth.Any(c => CippTestHelpers.StrEq(c, "state", "enabled")))
            {
                return new CippTestResult(TestStatus.Passed,
                    "Microsoft Authenticator method is not enabled in the tenant.");
            }

            var cfg = msAuth[0];
            var state = CippTestHelpers.PathStr(cfg, "featureSettings", "numberMatchingRequiredState", "state");
            var includeTargetId = CippTestHelpers.PathStr(cfg, "featureSettings", "numberMatchingRequiredState", "includeTarget", "id");

            var issues = new List<string>();
            if (!string.Equals(state, "enabled", StringComparison.OrdinalIgnoreCase))
            {
                issues.Add($"numberMatchingRequiredState.state is '{state ?? ""}' (expected 'enabled').");
            }
            if (!string.IsNullOrEmpty(includeTargetId) && !string.Equals(includeTargetId, "all_users", StringComparison.OrdinalIgnoreCase))
            {
                issues.Add($"numberMatchingRequiredState.includeTarget is '{includeTargetId}' (expected 'all_users').");
            }

            if (issues.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Microsoft Authenticator number matching is enabled and targets all users.");
            }

            return new CippTestResult(TestStatus.Failed,
                "Microsoft Authenticator number matching is not fully enforced:\n\n" + string.Join("\n", issues.Select(i => "- " + i)));
        }
    }
}
