using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (1.12) — EDR deployed: the Defender for Endpoint - Intune connector is enabled.
    /// Port of Invoke-CippTestSMB1001_1_12. Single source: MDEOnboarding (first record's
    /// partnerState).
    /// </summary>
    public sealed class SMB1001_1_12 : ICippTest
    {
        public string Id => "SMB1001_1_12";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var onboarding = data.Get("MDEOnboarding");
            if (!Any(onboarding))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "MDEOnboarding cache not found. This may be due to missing Defender for Endpoint licenses or data collection not yet completed.");
            }

            var connector = First(onboarding);
            var state = Str(connector, "partnerState");

            if (string.Equals(state, "enabled", System.StringComparison.OrdinalIgnoreCase))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"The Microsoft Defender for Endpoint - Intune connector is enabled (partnerState: {state}). Devices onboarded via Intune can report to MDE for EDR. If you are at L5, evidence the MDR service contract separately.");
            }

            var shown = string.IsNullOrEmpty(state) ? "unavailable" : state;
            return new CippTestResult(TestStatus.Failed,
                $"The Microsoft Defender for Endpoint - Intune connector is not enabled (partnerState: {shown}). Onboard tenant in Microsoft 365 Defender > Settings > Endpoints > Advanced features and connect Intune.");
        }
    }
}
