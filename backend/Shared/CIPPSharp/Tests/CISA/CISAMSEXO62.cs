using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.6.2 — Calendar details SHALL NOT be shared with all domains.
    /// Port of Invoke-CippTestCISAMSEXO62. An enabled sharing policy fails when any of its
    /// <c>Domains</c> entries is a wildcard (<c>^\*:</c>) that also matches
    /// <c>CalendarSharing(FreeBusyDetail|All)</c>.
    /// </summary>
    public sealed class CISAMSEXO62 : ICippTest
    {
        public string Id => "CISAMSEXO62";

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
                bool wildcardCalendar = false;
                foreach (var d in Arr(p, "Domains"))
                {
                    if (d.ValueKind != JsonValueKind.String) continue;
                    var s = d.GetString();
                    if (Match(s, "^\\*:") && Match(s, "CalendarSharing(FreeBusyDetail|All)")) { wildcardCalendar = true; break; }
                }
                if (wildcardCalendar) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: No sharing policies allow detailed calendar sharing with all domains.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} sharing policy/policies allow detailed calendar sharing with all domains:\n\n");
            sb.Append("| Policy Name | Enabled | Issue |\n");
            sb.Append("| :---------- | :------ | :---- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "Enabled")} | Allows detailed calendar sharing with all domains |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
