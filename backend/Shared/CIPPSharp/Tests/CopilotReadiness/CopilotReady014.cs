using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant has enabled DLP policies to protect sensitive data (governance prerequisite for Copilot).
    /// Port of Invoke-CippTestCopilotReady014. Single source: DlpCompliancePolicies.
    /// PS skips on `$null -eq $Policies` (type never collected), so the skip is keyed on Has().
    /// </summary>
    public sealed class CopilotReady014 : ICippTest
    {
        public string Id => "CopilotReady014";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("DlpCompliancePolicies"))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No DLP policy data found in database. The tenant may not have a Microsoft Purview/AIP license (M365 Business Premium, E3, or E5), or data collection may not yet have run.");
            }

            var policies = data.Get("DlpCompliancePolicies");
            var all = Items(policies).ToList();
            int enabledCount = all.Count(p => StrEq(p, "Mode", "Enable") && IsTrue(p, "Enabled"));

            if (enabledCount > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"**{enabledCount} enabled DLP polic{(enabledCount == 1 ? "y" : "ies")}** found in the tenant.\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var p in all.OrderBy(x => Str(x, "DisplayName") ?? "", StringComparer.OrdinalIgnoreCase))
                {
                    string isEnabled = (StrEq(p, "Mode", "Enable") && IsTrue(p, "Enabled")) ? "✅ Yes" : "No";
                    string workload = HasText(p, "Workload") ? Str(p, "Workload")! : "—";
                    rows.Add(new[] { Cell(Prop(p, "DisplayName")), workload, isEnabled });
                }
                sb.Append(Markdown.Table(new[] { "Policy", "Workload", "Enabled" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("No enabled DLP policies were found in this tenant.\n\n");
            if (all.Count > 0)
            {
                f.Append($"**{all.Count} polic{(all.Count == 1 ? "y exists" : "ies exist")}** but none are enabled.\n\n");
            }
            f.Append("Data Loss Prevention policies help protect sensitive information from being shared inappropriately — a critical control when Copilot can surface content broadly. ");
            f.Append("Enable or create DLP policies in the [Microsoft Purview compliance portal](https://compliance.microsoft.com/datalossprevention) before deploying Copilot.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
