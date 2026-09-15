using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.6.1 — Contact folders SHALL NOT be shared with all domains.
    /// Port of Invoke-CippTestCISAMSEXO61. An enabled sharing policy fails when any of its
    /// <c>Domains</c> entries matches <c>ContactsSharing</c>.
    /// </summary>
    public sealed class CISAMSEXO61 : ICippTest
    {
        public string Id => "CISAMSEXO61";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoSharingPolicy");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoSharingPolicy cache not found. Please refresh the cache for this tenant.");

            var failed = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!TruthyProp(p, "Enabled")) continue;
                bool hasContactSharing = false;
                foreach (var d in Arr(p, "Domains"))
                    if (d.ValueKind == JsonValueKind.String && Match(d.GetString(), "ContactsSharing")) { hasContactSharing = true; break; }
                if (hasContactSharing) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: No sharing policies allow contact folder sharing with external domains.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} sharing policy/policies allow contact folder sharing:\n\n");
            sb.Append("| Policy Name | Enabled | Issue |\n");
            sb.Append("| :---------- | :------ | :---- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "Enabled")} | Allows contact sharing with external domains |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
