using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guests cannot invite other guests.
    /// Port of Invoke-CippTestZTNA21791. AuthorizationPolicy allowInvitesFrom must not be 'everyone'.
    /// </summary>
    public sealed class ZTNA21791 : ICippTest
    {
        public string Id => "ZTNA21791";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("AuthorizationPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            var allowInvitesFrom = Str(policy, "allowInvitesFrom");
            if (!string.Equals(allowInvitesFrom, "everyone", System.StringComparison.OrdinalIgnoreCase))
                return new CippTestResult(TestStatus.Passed, $"Tenant restricts who can invite guests (Set to: {allowInvitesFrom})");

            return new CippTestResult(TestStatus.Failed, "Tenant allows any user including guests to invite other guests");
        }
    }
}
