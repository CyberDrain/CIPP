using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.11) — Comprehensive attachment filtering SHALL be applied.
    /// Port of Invoke-CippTestCIS_2_1_11. Passes when any malware policy has the file filter on
    /// with at least 168 blocked file types (90% of the CIS v7 186-extension list).
    /// </summary>
    public sealed class CIS_2_1_11 : ICippTest
    {
        public string Id => "CIS_2_1_11";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoMalwareFilterPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? compliant = null;
            foreach (var p in policies.EnumerateArray())
            {
                if (IsTrue(p, "EnableFileFilter") && ArrayCount(p, "FileTypes") >= 168)
                {
                    compliant = p;
                    break;
                }
            }

            if (compliant != null)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Comprehensive attachment filtering is applied — {ArrayCount(compliant.Value, "FileTypes")} file types blocked on '{Str(compliant.Value, "Identity")}'.");
            }

            JsonElement? def = null;
            foreach (var p in policies.EnumerateArray())
                if (IsTrue(p, "IsDefault")) { def = p; break; }
            if (def == null) def = FirstOrNull(policies);
            var d = def!.Value;

            return new CippTestResult(TestStatus.Failed,
                $"Attachment filter on '{Str(d, "Identity")}' is not comprehensive (EnableFileFilter: {Cell(Prop(d, "EnableFileFilter"))}, FileTypes count: {ArrayCount(d, "FileTypes")}, expected >= 168 — 90% of the CIS v7 186-extension list).");
        }
    }
}
