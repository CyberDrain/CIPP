using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Outbound cross-tenant access settings are configured.
    /// Port of Invoke-CippTestZTNA21790. The default outbound b2bCollaboration and b2bDirectConnect
    /// policies must block all users and all applications.
    /// </summary>
    public sealed class ZTNA21790 : ICippTest
    {
        public string Id => "ZTNA21790";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("CrossTenantAccessPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            bool collab = OutboundBlocked(policy, "b2bCollaborationOutbound");
            bool direct = OutboundBlocked(policy, "b2bDirectConnectOutbound");

            return collab && direct
                ? new CippTestResult(TestStatus.Passed, "Default cross-tenant access outbound policy blocks all access")
                : new CippTestResult(TestStatus.Failed, "Default cross-tenant access outbound policy has unrestricted access");
        }

        private static bool OutboundBlocked(JsonElement policy, string section)
        {
            var s = Nested(policy, section);
            var users = Nested(s, "usersAndGroups");
            var apps = Nested(s, "applications");
            bool usersBlocked = StrEq(users, "accessType", "blocked") && FirstTargetEquals(users, "AllUsers");
            bool appsBlocked = StrEq(apps, "accessType", "blocked") && FirstTargetEquals(apps, "AllApplications");
            return usersBlocked && appsBlocked;
        }

        private static bool FirstTargetEquals(JsonElement node, string value)
        {
            var targets = Nested(node, "targets");
            if (targets.ValueKind != JsonValueKind.Array || targets.GetArrayLength() == 0) return false;
            return string.Equals(AsString(Nested(targets[0], "target")), value, System.StringComparison.OrdinalIgnoreCase);
        }
    }
}
