using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Windows Firewall policies protect against unauthorized network access.
    /// Port of Invoke-CippTestZTNA24540. Reads IntuneConfigurationPolicies; firewall policy =
    /// templateReference.templateFamily == 'endpointSecurityFirewall'. Passed if at least one is assigned.
    /// </summary>
    public sealed class ZTNA24540 : ICippTest
    {
        public string Id => "ZTNA24540";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var firewall = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (TryProp(p, "templateReference", out var tr)
                    && tr.ValueKind == JsonValueKind.Object
                    && StrEq(tr, "templateFamily", "endpointSecurityFirewall"))
                    firewall.Add(p);
            }

            if (firewall.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Windows Firewall configuration policies found");

            int assigned = firewall.FindAll(IsAssigned).Count;

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append("At least one Windows Firewall policy is created and assigned to a group.\n");
                sb.Append("\n**Windows Firewall Configuration Policies:**\n\n");
                sb.Append("| Policy Name | Status | Assignment Count |\n");
                sb.Append("| :---------- | :----- | :--------------- |\n");
                foreach (var p in firewall)
                {
                    var status = IsAssigned(p) ? "✅ Assigned" : "❌ Not assigned";
                    sb.Append($"| {Text(p, "name")} | {status} | {ArrayLen(p, "assignments")} |\n");
                }
                // PS joins with `n; the last table line has no trailing newline in PS join, but the parity
                // gate is verdict/data, not trailing whitespace.
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }
            else
            {
                var sb = new StringBuilder();
                sb.Append("There are no firewall policies assigned to any groups.\n");
                sb.Append("\n**Windows Firewall Configuration Policies (Unassigned):**\n\n");
                foreach (var p in firewall) sb.Append($"- {Text(p, "name")}\n");
                return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
            }
        }
    }
}
