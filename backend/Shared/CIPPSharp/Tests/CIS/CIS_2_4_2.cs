using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.4.2) — Priority accounts SHALL have 'Strict protection' presets applied.
    /// Port of Invoke-CippTestCIS_2_4_2. Passes when the Strict preset security policy is enabled.
    /// </summary>
    public sealed class CIS_2_4_2 : ICippTest
    {
        public string Id => "CIS_2_4_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var presets = data.Get("ExoPresetSecurityPolicy");
            if (!Any(presets))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.");
            }

            bool strict = false;
            foreach (var p in presets.EnumerateArray())
            {
                if (LikeCI(Str(p, "Identity"), "*Strict Preset Security Policy*") && StrEq(p, "State", "Enabled"))
                {
                    strict = true;
                    break;
                }
            }

            if (strict)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Strict preset security policy is enabled. Confirm priority accounts are scoped into the rule (`Get-EOPProtectionPolicyRule -Identity 'Strict Preset Security Policy'`).");
            }

            return new CippTestResult(TestStatus.Failed,
                "Strict preset security policy is not enabled. Enable it in the Microsoft 365 Defender portal and scope priority accounts into the rule.");
        }
    }
}
