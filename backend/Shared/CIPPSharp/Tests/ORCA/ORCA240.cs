using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Outlook external tags are configured (ExternalInOutlook != 'Disabled').
    /// Port of Invoke-CippTestORCA240. Single source: ExoOrganizationConfig (first record).
    /// </summary>
    public sealed class ORCA240 : ICippTest
    {
        public string Id => "ORCA240";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoOrganizationConfig"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var config = Items(data.Get("ExoOrganizationConfig")).First();

            // PS: $Config.ExternalInOutlook -ne 'Disabled' → Passed. Missing/null is -ne 'Disabled' → Passed.
            if (!StrEq(config, "ExternalInOutlook", "Disabled"))
            {
                var sb = new StringBuilder();
                sb.Append("Outlook external tags are configured.\n\n");
                sb.Append($"**ExternalInOutlook:** {CellOf(config, "ExternalInOutlook")}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("Outlook external tags are NOT configured.\n\n");
            f.Append($"**ExternalInOutlook:** {CellOf(config, "ExternalInOutlook")}");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
