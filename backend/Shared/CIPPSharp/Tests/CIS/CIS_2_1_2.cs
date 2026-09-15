using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.2) — Common Attachment Types Filter SHALL be enabled.
    /// Port of Invoke-CippTestCIS_2_1_2. Inspects the default (or first) malware filter policy.
    /// </summary>
    public sealed class CIS_2_1_2 : ICippTest
    {
        public string Id => "CIS_2_1_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoMalwareFilterPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? def = null;
            foreach (var p in policies.EnumerateArray())
                if (IsTrue(p, "IsDefault")) { def = p; break; }
            if (def == null) def = FirstOrNull(policies);

            var policy = def!.Value;
            if (IsTrue(policy, "EnableFileFilter"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Common Attachment Types Filter is enabled on '{Str(policy, "Identity")}' with {ArrayCount(policy, "FileTypes")} file types blocked.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Common Attachment Types Filter is disabled on '{Str(policy, "Identity")}' (EnableFileFilter: {Cell(Prop(policy, "EnableFileFilter"))}).");
        }
    }
}
