using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Patch Operating Systems) — a Windows Update Ring policy is configured and assigned.
    /// Port of Invoke-CippTestE8_PatchOS_01. Reads IntuneConfigurationPolicies (settings-catalog
    /// update rings) and IntuneDeviceConfigurations (legacy windowsUpdateForBusinessConfiguration).
    /// Note: no Skipped branch — no data still yields Failed, matching the PS source.
    /// </summary>
    public sealed class E8_PatchOS_01 : ICippTest
    {
        public string Id => "E8_PatchOS_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configPolicies = data.Get("IntuneConfigurationPolicies");
            var legacyPolicies = data.Get("IntuneDeviceConfigurations");

            var updateRings = new List<JsonElement>();

            if (CippTestHelpers.Any(configPolicies))
            {
                foreach (var p in CippTestHelpers.Items(configPolicies))
                {
                    var ids = CippTestHelpers.Project(
                        CippTestHelpers.Project(CippTestHelpers.Arr(p, "settings"), "settingInstance"),
                        "settingDefinitionId");
                    bool match = ids.Any(e =>
                    {
                        if (e.ValueKind != JsonValueKind.String) return false;
                        var s = e.GetString();
                        return CippTestHelpers.ContainsCi(s, "windowsupdate") || CippTestHelpers.ContainsCi(s, "update_ring");
                    });
                    if (match) updateRings.Add(p);
                }
            }

            if (CippTestHelpers.Any(legacyPolicies))
            {
                foreach (var p in CippTestHelpers.Items(legacyPolicies))
                {
                    if (string.Equals(CippTestHelpers.Str(p, "@odata.type"),
                            "#microsoft.graph.windowsUpdateForBusinessConfiguration",
                            StringComparison.OrdinalIgnoreCase))
                    {
                        updateRings.Add(p);
                    }
                }
            }

            if (updateRings.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No Windows Update for Business / Update Ring configuration policy is deployed.");
            }

            int assigned = updateRings.Count(CippTestHelpers.HasAssignments);
            if (assigned > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{assigned} Windows Update Ring policy/policies are configured and assigned.");
            }
            return new CippTestResult(TestStatus.Failed,
                $"{updateRings.Count} Windows Update Ring policy/policies exist but none are assigned to any group/device.");
        }
    }
}
