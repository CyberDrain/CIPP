using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.2.1) — Only organizationally managed/approved public groups SHALL exist.
    /// Port of Invoke-CippTestCIS_1_2_1. Flags public Microsoft 365 (Unified) groups.
    /// </summary>
    public sealed class CIS_1_2_1 : ICippTest
    {
        public string Id => "CIS_1_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var groups = data.Get("Groups");
            if (!Any(groups))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Groups cache not found. Please refresh the cache for this tenant.");
            }

            var publicGroups = new List<JsonElement>();
            foreach (var g in groups.EnumerateArray())
            {
                if (!StrEq(g, "visibility", "Public")) continue;
                bool unified = false;
                foreach (var t in Arr(g, "groupTypes"))
                    if (t.ValueKind == JsonValueKind.String
                        && string.Equals(t.GetString(), "Unified", System.StringComparison.OrdinalIgnoreCase))
                    {
                        unified = true;
                        break;
                    }
                if (unified) publicGroups.Add(g);
            }

            if (publicGroups.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "No public Microsoft 365 (Unified) groups found in the tenant.");
            }

            var sb = new StringBuilder();
            sb.Append($"Found {publicGroups.Count} public Microsoft 365 group(s). Each public group's contents are visible to every user in the tenant — convert them to Private unless explicitly approved.\n\n");
            var rows = new List<IReadOnlyList<string>>();
            int shown = 0;
            foreach (var g in publicGroups)
            {
                if (shown++ >= 25) break;
                rows.Add(new[] { Str(g, "displayName") ?? "", Str(g, "mail") ?? "" });
            }
            sb.Append(Markdown.Table(new[] { "Display Name", "Mail" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
