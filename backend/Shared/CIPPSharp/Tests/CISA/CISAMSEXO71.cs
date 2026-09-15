using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.7.1 — External sender warnings SHALL be implemented.
    /// Port of Invoke-CippTestCISAMSEXO71. Passes when the org config's <c>ExternalInOutlook -eq $true</c>.
    /// </summary>
    public sealed class CISAMSEXO71 : ICippTest
    {
        public string Id => "CISAMSEXO71";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var config = data.Get("ExoOrganizationConfig");
            if (!Any(config))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.");

            var org = First(config);
            if (EqTrue(org, "ExternalInOutlook"))
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: External sender warnings are enabled in Outlook.");

            var body = "❌ **Fail**: External sender warnings are not enabled in Outlook.\n\n"
                + "**Current Setting:**\n"
                + $"- ExternalInOutlook: {Cell(org, "ExternalInOutlook")}";
            return new CippTestResult(TestStatus.Failed, body);
        }
    }
}
