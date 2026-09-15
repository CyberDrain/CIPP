using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Password protection for on-premises is enabled.
    /// Port of Invoke-CippTestZTNA21847. Cloud-only tenants pass; synced tenants are Skipped because
    /// the on-premises password protection settings are not available in the cache (the PS success
    /// path for synced tenants is dead code after an unconditional Skipped return).
    /// </summary>
    public sealed class ZTNA21847 : ICippTest
    {
        private const string SkipMessage =
            "No data found in database. This may be due to missing required licenses or data collection not yet completed.";

        public string Id => "ZTNA21847";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var org = data.Get("Organization");
            if (!Any(org)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            JsonElement first = default;
            foreach (var o in Items(org)) { first = o; break; }

            if (!IsTrue(first, "onPremisesSyncEnabled"))
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: This tenant is not synchronized to an on-premises environment.");

            // Synced tenant: on-premises password protection is not in the cache.
            return new CippTestResult(TestStatus.Skipped, SkipMessage);
        }
    }
}
