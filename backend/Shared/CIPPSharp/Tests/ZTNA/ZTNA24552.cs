using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Data on macOS is protected by firewall.
    /// Port of Invoke-CippTestZTNA24552. IntuneConfigurationPolicies for platform macOS whose settings
    /// choice value enables the firewall; Passed if at least one is assigned.
    /// </summary>
    public sealed class ZTNA24552 : ICippTest
    {
        private const string RequiredValue = "com.apple.security.firewall_enablefirewall_true";

        public string Id => "ZTNA24552";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!PropContains(p, "platforms", "macOS")) continue;
                if (FlattenContains(p, RequiredValue, "settings", "settingInstance", "choiceSettingValue", "value"))
                    matching.Add(p);
            }

            int assigned = matching.FindAll(IsAssigned).Count;

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append("At least one macOS Firewall policy is configured and assigned.\n");
                sb.Append("\n**macOS Firewall Policies:**\n\n");
                sb.Append("| Policy Name | Status | Assignment Count |\n");
                sb.Append("| :---------- | :----- | :--------------- |\n");
                foreach (var p in matching)
                {
                    var status = IsAssigned(p) ? "✅ Assigned" : "❌ Not assigned";
                    sb.Append($"| {Text(p, "name")} | {status} | {ArrayLen(p, "assignments")} |\n");
                }
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append("macOS Firewall policies exist but none are assigned.\n");
                sb.Append("\n**Unassigned Firewall Policies:**\n\n");
                foreach (var p in matching) sb.Append($"- {Text(p, "name")}\n");
                return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
            }

            return new CippTestResult(TestStatus.Failed, "No macOS Firewall policy is configured or assigned.");
        }
    }
}
