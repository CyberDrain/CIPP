using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (1.4) — Windows Update for Business profile deployed and assigned. Port of
    /// Invoke-CippTestSMB1001_1_4. Single source: IntuneDeviceConfigurations
    /// (@odata.type == '#microsoft.graph.windowsUpdateForBusinessConfiguration').
    /// </summary>
    public sealed class SMB1001_1_4 : ICippTest
    {
        public string Id => "SMB1001_1_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configs = data.Get("IntuneDeviceConfigurations");
            if (!Any(configs))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "IntuneDeviceConfigurations cache not found. This may be due to missing Intune licenses or data collection not yet completed.");
            }

            var update = new List<JsonElement>();
            foreach (var p in Items(configs))
                if (StrEq(p, "@odata.type", "#microsoft.graph.windowsUpdateForBusinessConfiguration"))
                    update.Add(p);

            if (update.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No Windows Update for Business configuration profiles found in Intune.");
            }

            int assigned = 0;
            foreach (var p in update) if (HasAssignments(p)) assigned++;

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{assigned} of {update.Count} Windows Update for Business profile(s) are assigned.\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var p in update)
                    rows.Add(new[] { CellOf(p, "displayName"), HasAssignments(p) ? "✅ Yes" : "❌ No" });
                sb.Append(Markdown.Table(new[] { "Profile Name", "Assigned" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }

            return new CippTestResult(TestStatus.Failed,
                $"Windows Update for Business profiles exist but none are assigned. Found {update.Count} unassigned profile(s).");
        }
    }
}
