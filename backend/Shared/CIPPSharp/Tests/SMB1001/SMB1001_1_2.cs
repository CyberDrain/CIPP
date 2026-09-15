using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (1.2) — Firewall configured and assigned on all devices. Port of
    /// Invoke-CippTestSMB1001_1_2. Single source: IntuneConfigurationPolicies
    /// (templateReference.templateFamily == 'endpointSecurityFirewall').
    /// </summary>
    public sealed class SMB1001_1_2 : ICippTest
    {
        public string Id => "SMB1001_1_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing Intune licenses or data collection not yet completed.");
            }

            var firewall = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                var tr = Prop(p, "templateReference");
                if (tr.ValueKind == JsonValueKind.Object && StrEq(tr, "templateFamily", "endpointSecurityFirewall"))
                    firewall.Add(p);
            }

            if (firewall.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No endpoint security firewall configuration policies found in Intune.");
            }

            int assigned = 0;
            foreach (var p in firewall) if (HasAssignments(p)) assigned++;

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{assigned} of {firewall.Count} firewall policy/policies are assigned.\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var p in firewall)
                    rows.Add(new[] { CellOf(p, "name"), HasAssignments(p) ? "✅ Yes" : "❌ No" });
                sb.Append(Markdown.Table(new[] { "Policy Name", "Assigned" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }

            return new CippTestResult(TestStatus.Failed,
                $"Firewall policies exist but none are assigned. Found {firewall.Count} unassigned policy/policies.");
        }
    }
}
