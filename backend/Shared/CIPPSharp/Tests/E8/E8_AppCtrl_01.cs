using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Application Control) — application control (WDAC / Smart App Control / AppLocker) is
    /// configured for Windows endpoints. Port of Invoke-CippTestE8_AppCtrl_01.
    /// Reads IntuneConfigurationPolicies; a policy counts when any of its setting definition ids
    /// contains applicationcontrol / smartappcontrol / applocker (case-insensitive substring).
    /// </summary>
    public sealed class E8_AppCtrl_01 : ICippTest
    {
        public string Id => "E8_AppCtrl_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configPolicies = data.Get("IntuneConfigurationPolicies");
            if (!CippTestHelpers.Any(configPolicies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Intune Configuration Policies cached for this tenant.");
            }

            var appControl = new List<JsonElement>();
            foreach (var p in CippTestHelpers.Items(configPolicies))
            {
                var ids = CippTestHelpers.Project(
                    CippTestHelpers.Project(CippTestHelpers.Arr(p, "settings"), "settingInstance"),
                    "settingDefinitionId");

                bool match = ids.Any(e =>
                {
                    if (e.ValueKind != JsonValueKind.String) return false;
                    var s = e.GetString();
                    return CippTestHelpers.ContainsCi(s, "applicationcontrol")
                        || CippTestHelpers.ContainsCi(s, "smartappcontrol")
                        || CippTestHelpers.ContainsCi(s, "applocker");
                });
                if (match) appControl.Add(p);
            }

            int assigned = appControl.Count(CippTestHelpers.HasAssignments);

            if (assigned > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{assigned} application-control policy/policies (WDAC/Smart App Control/AppLocker) are configured and assigned.");
            }
            if (appControl.Count > 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"{appControl.Count} application-control policy/policies exist but none are assigned.");
            }
            return new CippTestResult(TestStatus.Failed,
                "No WDAC, Smart App Control, or AppLocker configuration policy is deployed via Intune.");
        }
    }
}
