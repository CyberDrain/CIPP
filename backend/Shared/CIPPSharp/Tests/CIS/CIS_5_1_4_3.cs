using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.4.3) — GA role SHALL NOT be added as local administrator during Entra join.
    /// Port of Invoke-CippTestCIS_5_1_4_3. Single source: DeviceRegistrationPolicy (first record).
    /// PS grades <c>-not [bool]$enableGlobalAdmins</c>, so absent/false → Passed.
    /// </summary>
    public sealed class CIS_5_1_4_3 : ICippTest
    {
        public string Id => "CIS_5_1_4_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var drp = data.Get("DeviceRegistrationPolicy");
            if (!Any(drp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(drp)!.Value;
            var localAdmins = PropPath(cfg, "azureADJoin.localAdmins");
            bool enableGa = PsTruthyProp(localAdmins, "enableGlobalAdmins");

            if (!enableGa)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Global Administrators are not granted local admin during Entra join (enableGlobalAdmins: false).");
            }

            return new CippTestResult(TestStatus.Failed,
                "Global Administrators are granted local admin during Entra join (enableGlobalAdmins: true). Use the Microsoft Entra Joined Device Local Administrator role instead.");
        }
    }
}
