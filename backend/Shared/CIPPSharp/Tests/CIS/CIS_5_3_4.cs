using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.3.4) — Approval SHALL be required for Global Administrator role activation.
    /// Port of Invoke-CippTestCIS_5_3_4. Looks for a directory-scoped PIM role management policy whose
    /// Approval_EndUser_Assignment rule has isApprovalRequired = true.
    /// </summary>
    public sealed class CIS_5_3_4 : ICippTest
    {
        public string Id => "CIS_5_3_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("RoleManagementPolicies");
            var roles = data.Get("Roles");

            if (!Any(policies) || !Any(roles))
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (RoleManagementPolicies or Roles) not found.");

            if (HasApprovalPolicy(policies))
                return new CippTestResult(TestStatus.Passed,
                    "A PIM role management policy requires approval for activation. Verify it is scoped to Global Administrator.");

            return new CippTestResult(TestStatus.Failed,
                "No PIM role management policy with isApprovalRequired = true was found for the GA scope. Configure approval in PIM role settings for Global Administrator.");
        }

        internal static bool HasApprovalPolicy(JsonElement policies)
        {
            foreach (var p in policies.EnumerateArray())
            {
                if (!StrEq(p, "scopeId", "/") || !StrEq(p, "scopeType", "DirectoryRole")) continue;
                foreach (var rule in Arr(p, "rules"))
                {
                    if (StrEq(rule, "id", "Approval_EndUser_Assignment")
                        && LeafIsTrue(Path(rule, "setting", "isApprovalRequired")))
                        return true;
                }
            }
            return false;
        }
    }
}
