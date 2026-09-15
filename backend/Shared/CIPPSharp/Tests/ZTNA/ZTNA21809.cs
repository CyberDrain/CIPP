using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Admin consent workflow is enabled.
    /// Port of Invoke-CippTestZTNA21809. AdminConsentRequestPolicy.isEnabled must be true.
    /// </summary>
    public sealed class ZTNA21809 : ICippTest
    {
        public string Id => "ZTNA21809";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AdminConsentRequestPolicy");
            if (!Any(policy))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            bool isEnabled = false;
            foreach (var rec in Items(policy)) { isEnabled = IsTrue(rec, "isEnabled"); break; }

            if (isEnabled)
                return new CippTestResult(TestStatus.Passed, "Admin consent workflow is enabled.");

            return new CippTestResult(TestStatus.Failed,
                "Admin consent workflow is disabled.\n\nThe adminConsentRequestPolicy.isEnabled property is set to false.");
        }
    }
}
