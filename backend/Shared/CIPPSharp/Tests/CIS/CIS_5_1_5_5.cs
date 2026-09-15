using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.5.5) — New application passwords SHALL be system-generated. Port of
    /// Invoke-CippTestCIS_5_1_5_5. Single source: DefaultAppManagementPolicy (first record).
    /// </summary>
    public sealed class CIS_5_1_5_5 : ICippTest
    {
        public string Id => "CIS_5_1_5_5";

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
                if (StrEq(r, "restrictionType", "customPasswordAddition")) { restriction = r; break; }
            }

            if (!PsTruthyProp(cfg, "isEnabled"))
            {
                return new CippTestResult(TestStatus.Failed,
                    "The default app management policy is not enabled (isEnabled is false). Custom application passwords are not blocked, so new passwords are not required to be system-generated.");
            }
            if (restriction == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No customPasswordAddition restriction is configured under the application restrictions. Custom application passwords are not blocked.");
            }
            if (!StrEq(restriction.Value, "state", "enabled"))
            {
                return new CippTestResult(TestStatus.Failed,
                    $"The customPasswordAddition restriction is not enabled (state is '{Str(restriction.Value, "state")}'). Custom application passwords are not blocked, so new passwords are not required to be system-generated.");
            }

            return new CippTestResult(TestStatus.Passed,
                "The default app management policy is enabled and the customPasswordAddition restriction is enabled. Custom passwords are blocked, so new application passwords must be system-generated.");
        }
    }
}
