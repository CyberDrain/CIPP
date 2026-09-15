using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.5.2) — The admin consent workflow SHALL be enabled. Port of
    /// Invoke-CippTestCIS_5_1_5_2. Single source: AdminConsentRequestPolicy (first record).
    /// </summary>
    public sealed class CIS_5_1_5_2 : ICippTest
    {
        public string Id => "CIS_5_1_5_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AdminConsentRequestPolicy");
            if (!Any(policy))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "AdminConsentRequestPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(policy)!.Value;
            bool isEnabled = IsTrue(cfg, "isEnabled");
            int reviewers = ArrayCount(cfg, "reviewers");

            if (isEnabled && reviewers > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Admin consent workflow is enabled with {reviewers} reviewer(s).");
            }

            if (isEnabled)
            {
                return new CippTestResult(TestStatus.Failed,
                    "Admin consent workflow is enabled but no reviewers are configured. Add at least one reviewer.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Admin consent workflow is disabled (isEnabled: {Cell(Prop(cfg, "isEnabled"))}).");
        }
    }
}
