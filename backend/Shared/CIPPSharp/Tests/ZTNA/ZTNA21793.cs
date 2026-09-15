using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant restrictions v2 policy is configured.
    /// Port of Invoke-CippTestZTNA21793. CrossTenantAccessPolicy.tenantRestrictions must block all
    /// users and all applications.
    /// </summary>
    public sealed class ZTNA21793 : ICippTest
    {
        public string Id => "ZTNA21793";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("CrossTenantAccessPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            var tr = Nested(policy, "tenantRestrictions");
            if (tr.ValueKind != JsonValueKind.Object)
                return new CippTestResult(TestStatus.Failed, "Tenant Restrictions v2 policy is not configured");

            bool usersBlocked = StrEq(Nested(tr, "usersAndGroups"), "accessType", "blocked")
                && FirstTargetEquals(Nested(tr, "usersAndGroups"), "AllUsers");
            bool appsBlocked = StrEq(Nested(tr, "applications"), "accessType", "blocked")
                && FirstTargetEquals(Nested(tr, "applications"), "AllApplications");

            return usersBlocked && appsBlocked
                ? new CippTestResult(TestStatus.Passed, "Tenant Restrictions v2 policy is properly configured")
                : new CippTestResult(TestStatus.Failed, "Tenant Restrictions v2 policy is configured but not properly restricting all users and applications");
        }

        private static bool FirstTargetEquals(JsonElement node, string value)
        {
            var targets = Nested(node, "targets");
            if (targets.ValueKind != JsonValueKind.Array || targets.GetArrayLength() == 0) return false;
            return string.Equals(AsString(Nested(targets[0], "target")), value, System.StringComparison.OrdinalIgnoreCase);
        }
    }
}
