using System.Collections.Generic;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.8) — Cloud IAM configured with least privilege. Port of
    /// Invoke-CippTestSMB1001_2_8. Single source: AuthorizationPolicy (first record). Each
    /// self-service creation flag must be explicitly <c>false</c>; anything else (true OR absent)
    /// is an issue — matching PS <c>-ne $false</c>.
    /// </summary>
    public sealed class SMB1001_2_8 : ICippTest
    {
        public string Id => "SMB1001_2_8";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var auth = data.Get("AuthorizationPolicy");
            if (!Any(auth))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "AuthorizationPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = First(auth);
            var perms = Prop(cfg, "defaultUserRolePermissions");
            var issues = new List<string>();

            if (!IsFalse(perms, "allowedToCreateApps"))
                issues.Add($"Users can create app registrations (allowedToCreateApps: {CellOf(perms, "allowedToCreateApps")})");
            if (!IsFalse(perms, "allowedToCreateTenants"))
                issues.Add($"Users can create new M365 tenants (allowedToCreateTenants: {CellOf(perms, "allowedToCreateTenants")})");
            if (!IsFalse(perms, "allowedToCreateSecurityGroups"))
                issues.Add($"Users can create security groups (allowedToCreateSecurityGroups: {CellOf(perms, "allowedToCreateSecurityGroups")})");
            if (!IsFalse(cfg, "allowedToSignUpEmailBasedSubscriptions"))
                issues.Add($"Users can sign up for self-service subscriptions (allowedToSignUpEmailBasedSubscriptions: {CellOf(cfg, "allowedToSignUpEmailBasedSubscriptions")})");

            if (issues.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Cloud IAM is configured with least privilege — users cannot create app registrations, tenants, security groups, or self-service subscriptions.");
            }

            var body = "Cloud IAM grants users administrative-level capabilities that should be restricted to dedicated admin accounts:\n\n- "
                       + string.Join("\n- ", issues);
            return new CippTestResult(TestStatus.Failed, body);
        }
    }
}
