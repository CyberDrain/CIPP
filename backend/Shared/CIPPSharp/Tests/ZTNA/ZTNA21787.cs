using System;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Permissions to create new tenants are limited to the Tenant Creator role.
    /// Port of Invoke-CippTestZTNA21787. AuthorizationPolicy defaultUserRolePermissions
    /// allowedToCreateTenants must be explicitly false. Missing/true → Failed (PS <c>-eq $false</c>).
    /// </summary>
    public sealed class ZTNA21787 : ICippTest
    {
        public string Id => "ZTNA21787";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("AuthorizationPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            var leaf = Nested(policy, "defaultUserRolePermissions", "allowedToCreateTenants");
            bool isFalse = leaf.ValueKind == JsonValueKind.False
                || (leaf.ValueKind == JsonValueKind.String
                    && string.Equals(leaf.GetString(), "false", StringComparison.OrdinalIgnoreCase));

            return isFalse
                ? new CippTestResult(TestStatus.Passed, "Non-privileged users are restricted from creating tenants")
                : new CippTestResult(TestStatus.Failed, "Non-privileged users are allowed to create tenants");
        }
    }
}
