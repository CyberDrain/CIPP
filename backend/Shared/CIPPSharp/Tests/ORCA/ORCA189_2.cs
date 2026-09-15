using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe Links is not bypassed by transport rules. Port of Invoke-CippTestORCA189_2.
    /// Single source: ExoTransportRules. A bypass rule sets the header
    /// X-MS-Exchange-Organization-SkipSafeLinksProcessing to '1'.
    /// </summary>
    public sealed class ORCA189_2 : ICippTest
    {
        public string Id => "ORCA189_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoTransportRules"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var bypass = Items(data.Get("ExoTransportRules"))
                .Where(r => StrEq(r, "SetHeaderName", "X-MS-Exchange-Organization-SkipSafeLinksProcessing")
                            && StrEq(r, "SetHeaderValue", "1"))
                .ToList();

            if (bypass.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No transport rules are bypassing Safe Links processing.");

            var f = new StringBuilder();
            f.Append($"{bypass.Count} transport rules are bypassing Safe Links processing.\n\n");
            var rows = bypass.Select(r => (IReadOnlyList<string>)new[] { CellOf(r, "Name"), CellOf(r, "Priority") }).ToList();
            f.Append(Markdown.Table(new[] { "Rule Name", "Priority" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
