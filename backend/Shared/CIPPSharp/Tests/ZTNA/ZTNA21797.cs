using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Restrict access to high risk users.
    /// Port of Invoke-CippTestZTNA21797. Grades enabled CA policies targeting high user-risk (password
    /// change / block) against whether passwordless authentication is enabled: with passwordless on, a
    /// block policy is required; otherwise either control suffices.
    /// </summary>
    public sealed class ZTNA21797 : ICippTest
    {
        public string Id => "ZTNA21797";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            var authMethods = data.Get("AuthenticationMethodsPolicy");

            if (!Any(caPolicies) || !Any(authMethods))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var passwordChange = new List<JsonElement>();
            var block = new List<JsonElement>();
            var inactive = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                bool high = FlattenContains(p, "high", "conditions", "userRiskLevels");
                if (!high) continue;
                bool hasPwChange = FlattenContains(p, "passwordChange", "grantControls", "builtInControls");
                bool hasBlock = FlattenContains(p, "block", "grantControls", "builtInControls");
                bool enabled = StrEq(p, "state", "enabled");
                if (hasPwChange && enabled) passwordChange.Add(p);
                if (hasBlock && enabled) block.Add(p);
                if ((hasPwChange || hasBlock) && !enabled) inactive.Add(p);
            }

            var passwordlessMethods = new List<(string Name, string State, string Extra)>();
            foreach (var rec in Items(authMethods))
            {
                foreach (var method in Arr(rec, "authenticationMethodConfigurations"))
                {
                    bool isPasswordless = false;
                    string extra = "";
                    var mid = Str(method, "id");
                    var mstate = Str(method, "state");
                    if (string.Equals(mid, "fido2", System.StringComparison.OrdinalIgnoreCase))
                        isPasswordless = string.Equals(mstate, "enabled", System.StringComparison.OrdinalIgnoreCase);
                    if (string.Equals(mid, "x509Certificate", System.StringComparison.OrdinalIgnoreCase)
                        && string.Equals(mstate, "enabled", System.StringComparison.OrdinalIgnoreCase)
                        && StrEq(method, "x509CertificateAuthenticationDefaultMode", "x509CertificateMultiFactor"))
                    {
                        isPasswordless = true;
                        extra = " (Mode: x509CertificateMultiFactor)";
                    }
                    if (isPasswordless) passwordlessMethods.Add((mid ?? "", mstate ?? "", extra));
                }
            }

            bool passwordlessEnabled = passwordlessMethods.Count > 0;
            bool result = (!passwordlessEnabled && (passwordChange.Count + block.Count > 0))
                || (passwordlessEnabled && block.Count > 0);

            string text = result
                ? "Policies to restrict access for high risk users are properly implemented."
                : (passwordlessEnabled && block.Count == 0
                    ? "Passwordless authentication is enabled, but no policies to block high risk users are configured."
                    : "No policies found to protect against high risk users.");

            var md = new StringBuilder("\n## Passwordless Authentication Methods allowed in tenant\n\n");
            if (passwordlessMethods.Count > 0)
            {
                md.Append("| Authentication Method Name | State | Additional Info |\n");
                md.Append("| :------------------------ | :---- | :-------------- |\n");
                foreach (var m in passwordlessMethods)
                    md.Append($"| {m.Name} | {m.State} | {m.Extra} |\n");
            }
            else
            {
                md.Append("No passwordless authentication methods are enabled.\n");
            }

            md.Append("\n## Conditional Access Policies targeting high risk users\n\n");

            var allEnabled = new List<JsonElement>();
            allEnabled.AddRange(passwordChange);
            allEnabled.AddRange(block);

            if (allEnabled.Count > 0)
            {
                md.Append("| Conditional Access Policy Name | Status | Conditions |\n");
                md.Append("| :--------------------- | :----- | :--------- |\n");
                foreach (var p in allEnabled)
                    md.Append($"| {Text(p, "displayName")} | Enabled | {Conditions(p)} |\n");
            }

            if (inactive.Count > 0)
            {
                if (allEnabled.Count == 0)
                {
                    md.Append("No conditional access policies targeting high risk users found.\n\n");
                    md.Append("### Inactive policies targeting high risk users (not contributing to security posture):\n\n");
                    md.Append("| Conditional Access Policy Name | Status | Conditions |\n");
                    md.Append("| :--------------------- | :----- | :--------- |\n");
                }
                foreach (var p in inactive)
                {
                    var status = StrEq(p, "state", "enabledForReportingButNotEnforced") ? "Report-only" : "Disabled";
                    md.Append($"| {Text(p, "displayName")} | {status} | {Conditions(p)} |\n");
                }
            }
            else if (allEnabled.Count == 0)
            {
                md.Append("No conditional access policies targeting high risk users found.\n");
            }

            return new CippTestResult(result ? TestStatus.Passed : TestStatus.Failed, text + md.ToString());
        }

        private static string Conditions(JsonElement policy)
        {
            var sb = new StringBuilder("User Risk Level: High");
            if (FlattenContains(policy, "passwordChange", "grantControls", "builtInControls")) sb.Append(", Control: Password Change");
            if (FlattenContains(policy, "block", "grantControls", "builtInControls")) sb.Append(", Control: Block");
            return sb.ToString();
        }
    }
}
