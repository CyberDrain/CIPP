using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Entra Connect uses a service principal.
    /// Port of Invoke-CippTestZTNA24570. Skipped on no Organization data, when hybrid sync is not
    /// enabled (N/A), or when Roles are missing. Passed when the Directory Synchronization Accounts
    /// role contains no enabled user accounts.
    /// </summary>
    public sealed class ZTNA24570 : ICippTest
    {
        public string Id => "ZTNA24570";
        private const string DirSyncRoleTemplateId = "d29b2b05-8046-44ba-8758-1e26182fcf32";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var orgArr = data.Get("Organization");
            if (!Any(orgArr))
                return new CippTestResult(TestStatus.Skipped, "Unable to retrieve organization information from cache.");

            JsonElement org = default;
            foreach (var o in Items(orgArr)) { org = o; break; }

            if (!IsTrue(org, "onPremisesSyncEnabled"))
                return new CippTestResult(TestStatus.Skipped,
                    "✅ **N/A**: Hybrid identity synchronization is not enabled in this tenant.");

            var roles = data.Get("Roles");
            if (!Any(roles))
                return new CippTestResult(TestStatus.Skipped, "Unable to retrieve roles from cache.");

            JsonElement dirSyncRole = default;
            bool found = false;
            foreach (var role in Items(roles))
                if (StrEq(role, "roleTemplateId", DirSyncRoleTemplateId)) { dirSyncRole = role; found = true; break; }

            if (!found)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Error**: Unable to find Directory Synchronization Accounts role in cache.");

            var enabledUsers = new List<(string Display, string Upn)>();
            foreach (var member in Arr(dirSyncRole, "members"))
                if (StrEq(member, "@odata.type", "#microsoft.graph.user") && IsTrue(member, "accountEnabled"))
                    enabledUsers.Add((Text(member, "displayName"), Text(member, "userPrincipalName")));

            var lastRaw = Str(org, "onPremisesLastSyncDateTime");
            var lastSync = string.IsNullOrEmpty(lastRaw) ? "Never" : FormatDate(lastRaw!);

            if (enabledUsers.Count == 0)
            {
                var pass = new StringBuilder("✅ **Pass**: Hybrid identity is enabled and using a service principal for synchronization.\n\n");
                pass.Append($"**Last Sync**: {lastSync}\n\n");
                pass.Append("[Review configuration](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles)");
                return new CippTestResult(TestStatus.Passed, pass.ToString());
            }

            var sb = new StringBuilder($"❌ **Fail**: Hybrid identity is enabled but using {enabledUsers.Count} enabled user account(s) for synchronization.\n\n");
            sb.Append($"**Last Sync**: {lastSync}\n\n");
            sb.Append("## Directory Synchronization Accounts role members\n\n");
            sb.Append("| Display Name | User Principal Name | Enabled |\n");
            sb.Append("| :----------- | :------------------ | :------ |\n");
            foreach (var u in enabledUsers)
                sb.Append($"| {u.Display} | {u.Upn} | ✅ Yes |\n");
            sb.Append("\n[Migrate to service principal](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles)");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
