using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.3.4) — 'User owned apps and services' SHALL be restricted.
    /// Port of Invoke-CippTestCIS_1_3_4. Reads AppsAndServices (falls back to a Settings record),
    /// requires both the Office Store and app/services trials to be disabled.
    /// </summary>
    public sealed class CIS_1_3_4 : ICippTest
    {
        public string Id => "CIS_1_3_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            JsonElement? cfg = FirstOrNull(data.Get("AppsAndServices"));
            if (cfg == null)
            {
                foreach (var s in Items(data.Get("Settings")))
                {
                    if (StrEq(s, "id", "appsAndServices") || TryProp(s, "isOfficeStoreEnabled", out _))
                    {
                        cfg = s;
                        break;
                    }
                }
            }

            if (cfg == null
                || !TryProp(cfg.Value, "isOfficeStoreEnabled", out _)
                || !TryProp(cfg.Value, "isAppAndServicesTrialEnabled", out _))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "appsAndServices settings not present in cache. Please refresh the AppsAndServices (or Settings) cache for this tenant.");
            }

            var c = cfg.Value;
            var storeCell = Cell(Prop(c, "isOfficeStoreEnabled"));
            var trialsCell = Cell(Prop(c, "isAppAndServicesTrialEnabled"));

            if (IsFalse(c, "isOfficeStoreEnabled") && IsFalse(c, "isAppAndServicesTrialEnabled"))
            {
                return new CippTestResult(TestStatus.Passed,
                    "Office Store and trials are both disabled.\n\n- isOfficeStoreEnabled: false\n- isAppAndServicesTrialEnabled: false");
            }

            return new CippTestResult(TestStatus.Failed,
                $"User owned apps and services are not fully restricted.\n\n- isOfficeStoreEnabled: {storeCell} (expected: false)\n- isAppAndServicesTrialEnabled: {trialsCell} (expected: false)");
        }
    }
}
