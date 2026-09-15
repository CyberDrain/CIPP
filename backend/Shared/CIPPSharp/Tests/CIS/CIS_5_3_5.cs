using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.3.5) — Approval SHALL be required for Privileged Role Administrator activation.
    /// Port of Invoke-CippTestCIS_5_3_5. Same directory-scoped PIM approval check as CIS_5_3_4.
    /// </summary>
    public sealed class CIS_5_3_5 : ICippTest
    {
        public string Id => "CIS_5_3_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("RoleManagementPolicies");
            var roles = data.Get("Roles");

            if (!Any(policies) || !Any(roles))
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (RoleManagementPolicies or Roles) not found.");

            if (CIS_5_3_4.HasApprovalPolicy(policies))
                return new CippTestResult(TestStatus.Passed,
                    "A PIM role management policy requires approval for activation. Verify it is scoped to Privileged Role Administrator.");

            return new CippTestResult(TestStatus.Failed,
                "No PIM role management policy with isApprovalRequired = true was found. Configure approval in PIM role settings for Privileged Role Administrator.");
        }
    }
}
