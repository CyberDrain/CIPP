using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant has active sensitivity labels configured in Microsoft Purview.
    /// Port of Invoke-CippTestCopilotReady013. Single source: SensitivityLabels.
    /// PS skips on `$null -eq $Labels` (type never collected), so we key the skip on Has().
    /// </summary>
    public sealed class CopilotReady013 : ICippTest
    {
        public string Id => "CopilotReady013";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("SensitivityLabels"))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No sensitivity label data found in database. The tenant may not have a Microsoft Purview/AIP license (M365 Business Premium, E3, or E5), or data collection may not yet have run.");
            }

            var labels = data.Get("SensitivityLabels");
            var active = new List<JsonElement>();
            foreach (var l in Items(labels))
                if (IsTrue(l, "isActive")) active.Add(l);

            if (active.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"**{active.Count} active sensitivity label{(active.Count == 1 ? "" : "s")}** found in the tenant.\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var label in active.OrderBy(l => Int(l, "sensitivity")))
                {
                    var parent = Prop(label, "parent");
                    string parentName = (parent.ValueKind == JsonValueKind.Object && HasText(parent, "name"))
                        ? Str(parent, "name")! : "—";
                    string hasProtection = IsTrue(label, "hasProtection") ? "✅ Yes" : "No";
                    rows.Add(new[] { Cell(Prop(label, "name")), parentName, hasProtection });
                }
                sb.Append(Markdown.Table(new[] { "Label", "Parent", "Has Protection" }, rows));
                sb.Append("\nCopilot can respect and apply these labels when creating or summarizing content.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("No active sensitivity labels were found in this tenant.\n\n");
            f.Append("Sensitivity labels classify and protect organizational data — helping ensure Copilot-generated content is appropriately marked. ");
            f.Append("Configure labels in the [Microsoft Purview compliance portal](https://compliance.microsoft.com/informationprotection) before deploying Copilot.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
