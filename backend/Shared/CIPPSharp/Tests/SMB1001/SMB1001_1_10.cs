using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (1.10) — Untrusted Office macros disabled via an assigned ASR policy. Port of
    /// Invoke-CippTestSMB1001_1_10. Single source: IntuneConfigurationPolicies, drilling into
    /// the settings graph for the ASR macro/child-process block rules.
    /// </summary>
    public sealed class SMB1001_1_10 : ICippTest
    {
        private const string AsrDefId = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules";
        private const string Win32DefId = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros";
        private const string OfficeChildDefId = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses";

        public string Id => "SMB1001_1_10";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing Intune licenses or data collection not yet completed.");
            }

            // ASR policies: windows10 platform AND the ASR rules setting definition present.
            var asr = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!Like(Str(p, "platforms"), "*windows10*")) continue;
                var defIds = Chain(p, "settings", "settingInstance", "settingDefinitionId");
                if (defIds.Any(x => ValEq(x, AsrDefId))) asr.Add(p);
            }

            if (asr.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No Attack Surface Reduction policies found. ASR rules block Office macro abuse, which SMB1001 1.10 requires.");
            }

            // Macro-protected: at least one of the two block/warn child rules enabled.
            var macroProtected = new List<JsonElement>();
            foreach (var p in asr)
            {
                var children = Chain(p, "settings", "settingInstance", "groupSettingCollectionValue", "children").ToList();
                bool win32 = children
                    .Where(c => StrEq(c, "settingDefinitionId", Win32DefId))
                    .SelectMany(c => Chain(c, "choiceSettingValue", "value"))
                    .Any(v => LikeVal(v, "*_block") || LikeVal(v, "*_warn"));
                bool officeChild = children
                    .Where(c => StrEq(c, "settingDefinitionId", OfficeChildDefId))
                    .SelectMany(c => Chain(c, "choiceSettingValue", "value"))
                    .Any(v => LikeVal(v, "*_block") || LikeVal(v, "*_warn"));
                if (win32 || officeChild) macroProtected.Add(p);
            }

            if (macroProtected.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "ASR policies exist but none enable the Office macro protection rules (Block Win32 API calls from Office macros / Block Office child processes).");
            }

            int assigned = macroProtected.Count(HasAssignments);
            if (assigned > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{assigned} ASR policy/policies are assigned with Office macro protection rules enabled.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"ASR policies with Office macro protection exist but are not assigned. Found {macroProtected.Count} unassigned policy/policies.");
        }

        private static bool LikeVal(JsonElement v, string pattern)
        {
            var s = v.ValueKind == JsonValueKind.String ? v.GetString()
                  : (v.ValueKind == JsonValueKind.Null || v.ValueKind == JsonValueKind.Undefined ? null : v.GetRawText());
            return Like(s, pattern);
        }
    }
}
