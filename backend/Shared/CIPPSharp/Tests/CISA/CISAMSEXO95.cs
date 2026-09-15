using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.9.5 — At a minimum, click-to-run files SHOULD be blocked (.cmd, .exe, .vbe).
    /// Port of Invoke-CippTestCISAMSEXO95. A policy fails when file filtering is not enabled
    /// (<c>-not EnableFileFilter</c>) or when any of the required types is <c>-notin FileTypes</c>.
    /// </summary>
    public sealed class CISAMSEXO95 : ICippTest
    {
        private static readonly string[] RequiredBlockedTypes = { "cmd", "exe", "vbe" };

        public string Id => "CISAMSEXO95";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoMalwareFilterPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.");

            // Each failed row carries the three cells the PS test renders.
            var failed = new List<(string Name, string FileFilter, string Missing)>();

            foreach (var p in Items(policies))
            {
                var name = Cell(p, "Name");

                if (NotTruthyProp(p, "EnableFileFilter"))
                {
                    // PS: 'File Filter Enabled' = $false → falsy → renders the Issue text; Missing → 'N/A'.
                    failed.Add((name, "File filtering not enabled", "N/A"));
                    continue;
                }

                var blocked = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var t in Arr(p, "FileTypes"))
                    if (t.ValueKind == JsonValueKind.String) blocked.Add(t.GetString() ?? "");

                var missing = new List<string>();
                foreach (var req in RequiredBlockedTypes)
                    if (!blocked.Contains(req)) missing.Add(req);

                if (missing.Count > 0)
                {
                    // PS: 'File Filter Enabled' = $true → renders "True"; Missing → joined list.
                    failed.Add((name, "True", string.Join(", ", missing)));
                }
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: All malware filter policies block click-to-run files (.exe, .cmd, .vbe).");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} malware filter policy/policies do not properly block click-to-run executables:\n\n");
            sb.Append("| Policy Name | File Filter Enabled | Missing Blocked Types |\n");
            sb.Append("| :---------- | :------------------ | :-------------------- |\n");
            foreach (var f in failed)
                sb.Append($"| {f.Name} | {f.FileFilter} | {f.Missing} |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
