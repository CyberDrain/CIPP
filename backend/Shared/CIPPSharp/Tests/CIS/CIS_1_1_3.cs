using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.1.3) — Between two and four global admins SHALL be designated.
    /// Port of Invoke-CippTestCIS_1_1_3.
    /// </summary>
    public sealed class CIS_1_1_3 : ICippTest
    {
        public string Id => "CIS_1_1_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("Roles"))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Roles) not found. Please refresh the cache for this tenant.");
            }

            var ga = GlobalAdminRole(data);
            if (ga == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "Global Administrator role not found in tenant role definitions.");
            }

            int count = CollectGaUserIds(data, ga.Value).Count;

            if (count >= 2 && count <= 4)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Tenant has {count} Global Administrator(s) — within the recommended 2–4 range.");
            }
            if (count < 2)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"Tenant has only {count} Global Administrator(s). At least 2 are required for redundancy.");
            }
            return new CippTestResult(TestStatus.Failed,
                $"Tenant has {count} Global Administrator(s). Maximum recommended is 4 — reduce role spread to lower the attack surface.");
        }
    }
}
