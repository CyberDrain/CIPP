using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guests have restricted access to directory objects.
    /// Port of Invoke-CippTestZTNA21792. AuthorizationPolicy guestUserRoleId must be the restricted
    /// guest role template id.
    /// </summary>
    public sealed class ZTNA21792 : ICippTest
    {
        private const string GuestRestrictedRoleId = "2af84b1e-32c8-42b7-82bc-daa82404023b";

        public string Id => "ZTNA21792";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("AuthorizationPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            return StrEq(policy, "guestUserRoleId", GuestRestrictedRoleId)
                ? new CippTestResult(TestStatus.Passed, "Guest user access is properly restricted")
                : new CippTestResult(TestStatus.Failed, "Guest user access is not restricted");
        }
    }
}
