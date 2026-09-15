using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.4.4) — Local administrator assignment SHALL be limited during Entra join.
    /// Port of Invoke-CippTestCIS_5_1_4_4. Single source: DeviceRegistrationPolicy (first record).
    /// </summary>
    public sealed class CIS_5_1_4_4 : ICippTest
    {
        public string Id => "CIS_5_1_4_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var drp = data.Get("DeviceRegistrationPolicy");
            if (!Any(drp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(drp)!.Value;
            var regType = Str(PropPath(cfg, "azureADJoin.localAdmins.registeringUsers"), "@odata.type");

            if (InListCI(regType,
                "#microsoft.graph.enumeratedDeviceRegistrationMembership",
                "#microsoft.graph.noDeviceRegistrationMembership"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Local admin assignment for registering users is restricted (type: {regType}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Local admin assignment for registering users is set to All (type: {regType}). Restrict to Selected or None.");
        }
    }
}
