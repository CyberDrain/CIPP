using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Resource-specific consent is restricted.
    /// Port of Invoke-CippTestZTNA21810. Passed when the Teams RSC permission grant policy is NOT
    /// assigned to the default user role (state DisabledForAllApps).
    /// </summary>
    public sealed class ZTNA21810 : ICippTest
    {
        private const string TeamPermission =
            "managepermissiongrantsforownedresource.microsoft-dynamically-managed-permissions-for-team";

        public string Id => "ZTNA21810";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authPolicy = data.Get("AuthorizationPolicy");
            if (!Any(authPolicy))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            bool hasTeamPermission = false;
            foreach (var rec in Items(authPolicy))
            {
                if (ArrContains(rec, "permissionGrantPolicyIdsAssignedToDefaultUserRole", TeamPermission))
                    hasTeamPermission = true;
                break; // singleton
            }

            string state = hasTeamPermission ? "EnabledForAllApps" : "DisabledForAllApps";

            if (state == "DisabledForAllApps")
                return new CippTestResult(TestStatus.Passed,
                    $"Resource-Specific Consent is restricted.\n\nThe current state is {state}.");

            return new CippTestResult(TestStatus.Failed,
                $"Resource-Specific Consent is not restricted.\n\nThe current state is {state}.");
        }
    }
}
