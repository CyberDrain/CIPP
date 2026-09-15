using System;
using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// User consent settings are restricted.
    /// Port of Invoke-CippTestZTNA21776. AuthorizationPolicy records whose defaultUserRolePermissions
    /// permissionGrantPoliciesAssigned start with 'ManagePermissionGrantsForSelf'. Passed when no such
    /// policy is assigned (consent disabled) or it is the low-impact default.
    /// </summary>
    public sealed class ZTNA21776 : ICippTest
    {
        public string Id => "ZTNA21776";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("AuthorizationPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matched = new List<JsonElement>();
            foreach (var rec in Items(arr))
            {
                var assigned = FlattenStrings(rec, "defaultUserRolePermissions", "permissionGrantPoliciesAssigned");
                if (assigned.Exists(s => s.StartsWith("ManagePermissionGrantsForSelf", StringComparison.OrdinalIgnoreCase)))
                    matched.Add(rec);
            }

            bool noMatch = matched.Count == 0;
            bool lowImpact = false;
            foreach (var rec in matched)
            {
                var assigned = FlattenStrings(rec, "defaultUserRolePermissions", "permissionGrantPoliciesAssigned");
                if (assigned.Exists(s => string.Equals(s, "managePermissionGrantsForSelf.microsoft-user-default-low", StringComparison.OrdinalIgnoreCase)))
                {
                    lowImpact = true;
                    break;
                }
            }

            if (noMatch || lowImpact)
                return new CippTestResult(TestStatus.Passed,
                    noMatch ? "User consent is disabled" : "User consent restricted to verified publishers and low-impact permissions");

            return new CippTestResult(TestStatus.Failed, "Users can consent to any application");
        }
    }
}
