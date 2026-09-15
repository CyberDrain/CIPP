namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 7.0.0 (5.1.8.1) — Password hash sync SHALL be enabled for hybrid deployments (Manual).
    /// Reads Organization + Domains (both CippReportingDB types). Cloud-only tenants (no on-prem sync)
    /// pass as not-applicable; hybrid tenants Skip because PHS state isn't exposed via Graph.
    /// </summary>
    public sealed class CIS_5_1_8_1 : ICippTest
    {
        public string Id => "CIS_5_1_8_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var org = data.Get("Organization");
            var domains = data.Get("Domains");

            // PS: -not $Org -or -not $Domains (empty collection is falsy)
            if (!CippTestHelpers.Any(org) || !CippTestHelpers.Any(domains))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Organization or Domains) not found. Please refresh the cache for this tenant.");
            }

            var orgCfg = System.Linq.Enumerable.First(CippTestHelpers.Items(org));
            var isHybrid = CippTestHelpers.IsTrue(orgCfg, "onPremisesSyncEnabled");

            if (!isHybrid)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Tenant is cloud-only (onPremisesSyncEnabled: false) — recommendation does not apply.");
            }

            return new CippTestResult(TestStatus.Skipped,
                "Tenant has on-prem sync enabled, but password hash sync (PHS) state is not exposed via Graph and must be verified manually.\n\n" +
                "```powershell\n" +
                "# On the Entra Connect Sync server:\n" +
                "Get-ADSyncAADCompanyFeature\n" +
                "```\n\n" +
                "`PasswordHashSync` should be `True`.");
        }
    }
}
