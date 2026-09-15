using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Attack Surface Reduction rules are applied to Windows devices.
    /// Port of Invoke-CippTestZTNA24574. IntuneConfigurationPolicies (windows10/mdm/microsoftSense)
    /// that configure ASR rules; the obfuscated-scripts and Win32-macro rules must both be set to
    /// block/warn and assigned.
    /// </summary>
    public sealed class ZTNA24574 : ICippTest
    {
        private const string AsrSetting = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules";
        private const string ObfuscatedRule = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutionofpotentiallyobfuscatedscripts";
        private const string Win32Rule = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros";

        public string Id => "ZTNA24574";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var senseWin = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (PropContains(p, "platforms", "windows10") && PropContains(p, "technologies", "mdm")
                    && PropContains(p, "technologies", "microsoftSense"))
                    senseWin.Add(p);

            if (senseWin.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Windows ASR policies found");

            var asr = new List<JsonElement>();
            foreach (var p in senseWin)
                if (FlattenStrings(p, "settings", "settingInstance", "settingDefinitionId").Contains(AsrSetting))
                    asr.Add(p);

            if (asr.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Attack Surface Reduction policies found");

            bool assignedObfuscated = false, assignedWin32 = false;
            foreach (var p in asr)
            {
                bool a = IsAssigned(p);
                if (a && RuleBlockOrWarn(p, ObfuscatedRule)) assignedObfuscated = true;
                if (a && RuleBlockOrWarn(p, Win32Rule)) assignedWin32 = true;
            }

            if (assignedObfuscated && assignedWin32)
                return new CippTestResult(TestStatus.Passed,
                    "ASR policies are configured and assigned with required rules (obfuscated scripts and Win32 API calls from macros)");

            if (assignedObfuscated || assignedWin32)
            {
                var missing = (assignedObfuscated ? "" : "obfuscated scripts rule ") + (assignedWin32 ? "" : "Win32 API calls rule");
                return new CippTestResult(TestStatus.Failed, $"ASR policies partially configured. Missing: {missing}");
            }

            return new CippTestResult(TestStatus.Failed, "ASR policies found but not properly configured or assigned for required rules");
        }

        private static bool RuleBlockOrWarn(JsonElement policy, string settingId)
        {
            foreach (var child in Flatten(policy, "settings", "settingInstance", "groupSettingCollectionValue", "children"))
            {
                if (!StrEq(child, "settingDefinitionId", settingId)) continue;
                var value = NestedStr(child, "choiceSettingValue", "value");
                if (value != null && (value.EndsWith("_block", System.StringComparison.OrdinalIgnoreCase)
                    || value.EndsWith("_warn", System.StringComparison.OrdinalIgnoreCase)))
                    return true;
            }
            return false;
        }
    }
}
