using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Local administrator credentials on Windows are protected by Windows LAPS.
    /// Port of Invoke-CippTestZTNA24560. IntuneConfigurationPolicies: endpointSecurityAccountProtection
    /// template on windows10 that configure LAPS backup directory + automatic account management, and
    /// are assigned.
    /// </summary>
    public sealed class ZTNA24560 : ICippTest
    {
        public string Id => "ZTNA24560";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var windows = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (NestedStr(p, "templateReference", "templateFamily") is string fam
                    && string.Equals(fam, "endpointSecurityAccountProtection", System.StringComparison.OrdinalIgnoreCase)
                    && PropContains(p, "platforms", "windows10"))
                    windows.Add(p);
            }

            if (windows.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Windows LAPS policies found");

            var laps = new List<JsonElement>();
            foreach (var p in windows)
            {
                var ids = FlattenStrings(p, "settings", "settingInstance", "settingDefinitionId");
                if (ids.Contains("device_vendor_msft_laps_policies_backupdirectory")
                    || ids.Contains("device_vendor_msft_laps_policies_automaticaccountmanagementenabled"))
                    laps.Add(p);
            }

            if (laps.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No LAPS policies configured");

            var compliant = new List<JsonElement>();
            foreach (var p in laps)
            {
                var ids = FlattenStrings(p, "settings", "settingInstance", "settingDefinitionId");
                var choiceValues = FlattenStrings(p, "settings", "settingInstance", "choiceSettingValue", "value");
                bool hasBackupDir = ids.Contains("device_vendor_msft_laps_policies_backupdirectory");
                bool hasEntra = choiceValues.Contains("device_vendor_msft_laps_policies_backupdirectory_1");
                bool hasAd = choiceValues.Contains("device_vendor_msft_laps_policies_backupdirectory_2");
                bool hasAuto = choiceValues.Contains("device_vendor_msft_laps_policies_automaticaccountmanagementenabled_true");
                if (hasBackupDir && (hasEntra || hasAd) && hasAuto) compliant.Add(p);
            }

            int assignedCompliant = compliant.FindAll(IsAssigned).Count;

            if (assignedCompliant > 0)
                return new CippTestResult(TestStatus.Passed,
                    $"Cloud LAPS policy is assigned and enforced. Found {assignedCompliant} compliant and assigned policy/policies");

            if (compliant.Count > 0)
                return new CippTestResult(TestStatus.Failed,
                    $"Cloud LAPS policy exists but is not assigned. Found {compliant.Count} compliant but unassigned policy/policies");

            return new CippTestResult(TestStatus.Failed, "Cloud LAPS policy is not configured correctly or not enforced");
        }
    }
}
