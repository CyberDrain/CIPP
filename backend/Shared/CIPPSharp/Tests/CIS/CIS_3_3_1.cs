using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (3.3.1) — Information Protection sensitivity label policies SHALL be published.
    /// Port of Invoke-CippTestCIS_3_3_1. Single source: SensitivityLabels. Passed when at least one
    /// label appears published (IsValid true or a PolicyName present).
    /// </summary>
    public sealed class CIS_3_3_1 : ICippTest
    {
        public string Id => "CIS_3_3_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var labels = data.Get("SensitivityLabels");
            if (!Any(labels))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "SensitivityLabels cache not found. Please refresh the cache for this tenant.");
            }

            int published = 0;
            foreach (var l in labels.EnumerateArray())
            {
                if (BoolEq(l, "IsValid", true) || HasText(l, "PolicyName")) published++;
            }

            if (published > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{published} sensitivity label(s) appear to be published in the tenant.");
            }

            return new CippTestResult(TestStatus.Failed,
                "No published sensitivity labels were found. Create and publish a label set covering at least Public / Internal / Confidential.");
        }
    }
}
