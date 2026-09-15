using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (1.3) — Antivirus installed and assigned on all devices. Port of
    /// Invoke-CippTestSMB1001_1_3. Single source: IntuneConfigurationPolicies
    /// (templateReference.templateFamily == 'endpointSecurityAntivirus').
    /// </summary>
    public sealed class SMB1001_1_3 : ICippTest
    {
        public string Id => "SMB1001_1_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing Intune licenses or data collection not yet completed.");
            }

            var av = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                var tr = Prop(p, "templateReference");
                if (tr.ValueKind == JsonValueKind.Object && StrEq(tr, "templateFamily", "endpointSecurityAntivirus"))
                    av.Add(p);
            }

            if (av.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No endpoint security antivirus configuration policies found in Intune.");
            }

            int assigned = 0;
            foreach (var p in av) if (HasAssignments(p)) assigned++;

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{assigned} of {av.Count} antivirus policy/policies are assigned.\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var p in av)
                {
                    var plat = HasText(p, "platforms") ? Str(p, "platforms")! : "unknown";
                    rows.Add(new[] { CellOf(p, "name"), plat, HasAssignments(p) ? "✅ Yes" : "❌ No" });
                }
                sb.Append(Markdown.Table(new[] { "Policy Name", "Platform", "Assigned" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }

            return new CippTestResult(TestStatus.Failed,
                $"Antivirus policies exist but none are assigned. Found {av.Count} unassigned policy/policies.");
        }
    }
}
