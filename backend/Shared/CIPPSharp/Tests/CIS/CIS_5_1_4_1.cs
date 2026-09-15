using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.4.1) — Ability to join devices to Entra SHALL be restricted. Port of
    /// Invoke-CippTestCIS_5_1_4_1. Single source: DeviceRegistrationPolicy (first record).
    /// </summary>
    public sealed class CIS_5_1_4_1 : ICippTest
    {
        public string Id => "CIS_5_1_4_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var drp = data.Get("DeviceRegistrationPolicy");
            if (!Any(drp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(drp)!.Value;
            var joinType = Str(PropPath(cfg, "azureADJoin.allowedToJoin"), "@odata.type");

            if (InListCI(joinType,
                "#microsoft.graph.enumeratedDeviceRegistrationMembership",
                "#microsoft.graph.noDeviceRegistrationMembership"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Entra device join is restricted (allowedToJoin type: {joinType}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Entra device join is open to All users (allowedToJoin type: {joinType}). Restrict to Selected or None.");
        }
    }
}
