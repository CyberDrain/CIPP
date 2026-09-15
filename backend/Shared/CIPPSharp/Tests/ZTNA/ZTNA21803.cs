using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Migrate from legacy MFA and SSPR policies.
    /// Port of Invoke-CippTestZTNA21803. Grades AuthenticationMethodsPolicy.policyMigrationState:
    /// migrationComplete = Passed, migrationInProgress = Investigate (non-standard status passed
    /// through verbatim), anything else = Failed.
    /// </summary>
    public sealed class ZTNA21803 : ICippTest
    {
        public string Id => "ZTNA21803";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            // Singleton — read the first record's migration state.
            string? state = null;
            foreach (var rec in Items(authMethods)) { state = Str(rec, "policyMigrationState"); break; }

            if (string.Equals(state, "migrationComplete", System.StringComparison.OrdinalIgnoreCase))
                return new CippTestResult(TestStatus.Passed,
                    "Tenant has migrated from legacy MFA and SSPR policies to authentication methods policy");

            if (string.Equals(state, "migrationInProgress", System.StringComparison.OrdinalIgnoreCase))
                return new CippTestResult("Investigate",
                    "Tenant migration from legacy MFA and SSPR policies is in progress");

            return new CippTestResult(TestStatus.Failed,
                $"Tenant has not migrated from legacy MFA and SSPR policies (state: {state})");
        }
    }
}
