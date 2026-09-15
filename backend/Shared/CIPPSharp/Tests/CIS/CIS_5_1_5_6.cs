using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.5.6) — Maximum certificate lifetime for applications SHALL NOT exceed 180 days.
    /// Port of Invoke-CippTestCIS_5_1_5_6. Single source: DefaultAppManagementPolicy (first record).
    /// maxLifetime is an ISO-8601 duration (parsed with XmlConvert, matching PS).
    /// </summary>
    public sealed class CIS_5_1_5_6 : ICippTest
    {
        public string Id => "CIS_5_1_5_6";

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
            foreach (var r in Items(PropPath(cfg, "applicationRestrictions.keyCredentials")))
            {
                if (StrEq(r, "restrictionType", "asymmetricKeyLifetime")) { restriction = r; break; }
            }

            if (!PsTruthyProp(cfg, "isEnabled"))
            {
                return new CippTestResult(TestStatus.Failed,
                    "The default app management policy is not enabled (isEnabled is false). A maximum certificate lifetime is not enforced for applications.");
            }
            if (restriction == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No asymmetricKeyLifetime restriction is configured under the application key credential restrictions. A maximum certificate lifetime is not enforced.");
            }
            if (!StrEq(restriction.Value, "state", "enabled"))
            {
                return new CippTestResult(TestStatus.Failed,
                    $"The asymmetricKeyLifetime restriction is not enabled (state is '{Str(restriction.Value, "state")}'). A maximum certificate lifetime is not enforced for applications.");
            }

            var maxLifetime = Str(restriction.Value, "maxLifetime");
            if (string.IsNullOrWhiteSpace(maxLifetime))
            {
                return new CippTestResult(TestStatus.Failed,
                    "The asymmetricKeyLifetime restriction is enabled but no maxLifetime value is set.");
            }

            double maxDays = System.Xml.XmlConvert.ToTimeSpan(maxLifetime).TotalDays;
            if (maxDays <= 180)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"The asymmetricKeyLifetime restriction is enabled with a maximum lifetime of {maxLifetime} ({(int)maxDays} days), which does not exceed 180 days.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"The asymmetricKeyLifetime restriction is enabled but the maximum lifetime of {maxLifetime} ({(int)maxDays} days) exceeds 180 days.");
        }
    }
}
