using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.5.3) — Password addition SHALL be blocked for applications. Port of
    /// Invoke-CippTestCIS_5_1_5_3. Single source: DefaultAppManagementPolicy (first record).
    /// </summary>
    public sealed class CIS_5_1_5_3 : ICippTest
    {
        public string Id => "CIS_5_1_5_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("DefaultAppManagementPolicy");
            if (!Any(policy))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DefaultAppManagementPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(policy)!.Value;
            JsonElement? restriction = null;
            foreach (var r in Items(PropPath(cfg, "applicationRestrictions.passwordCredentials")))
            {
                if (StrEq(r, "restrictionType", "passwordAddition")) { restriction = r; break; }
            }

            if (!PsTruthyProp(cfg, "isEnabled"))
            {
                return new CippTestResult(TestStatus.Failed,
                    "The default app management policy is not enabled (isEnabled is false). Password addition is not blocked for applications.");
            }
            if (restriction == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No passwordAddition restriction is configured under the application restrictions. Password addition is not blocked.");
            }
            if (!StrEq(restriction.Value, "state", "enabled"))
            {
                return new CippTestResult(TestStatus.Failed,
                    $"The passwordAddition restriction is not enabled (state is '{Str(restriction.Value, "state")}'). Password addition is not blocked for applications.");
            }

            return new CippTestResult(TestStatus.Passed,
                "The default app management policy is enabled and the passwordAddition restriction is enabled. Password addition is blocked for applications.");
        }
    }
}
