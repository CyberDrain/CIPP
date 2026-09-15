using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Authentication Methods - Policy Migration. Port of Invoke-CippTestEIDSCAAG01. Source: AuthenticationMethodsPolicy.</summary>
    public sealed class EIDSCAAG01 : ICippTest
    {
        public string Id => "EIDSCAAG01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationMethodsPolicy");
            if (!Any(policy)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var record = First(policy);
            var migrationState = PathStr(record, "policyMigrationState");

            // PS: $MigrationState -in @('migrationComplete', '') — a missing value ($null) is NOT in the set.
            if (migrationState != null && (migrationState.Length == 0 || StrIn(migrationState, "migrationComplete")))
                return new CippTestResult(TestStatus.Passed,
                    $"Policy migration is complete or not applicable: {migrationState}");

            var result = $@"The authentication methods policy migration should be complete.

**Current Configuration:**
- policyMigrationState: {PathCell(record, "policyMigrationState")}

**Recommended Configuration:**
- policyMigrationState: migrationComplete or empty

Complete the migration to use the modern authentication methods policy.";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
