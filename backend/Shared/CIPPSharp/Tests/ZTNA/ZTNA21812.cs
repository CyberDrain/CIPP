using System.Collections.Generic;
using System.Text;

namespace CIPP.Tests
{
    /// <summary>
    /// Maximum number of Global Administrators doesn't exceed five users.
    /// Port of Invoke-CippTestZTNA21812. Counts Global Administrator members that are users or
    /// service principals; passes when five or fewer.
    /// </summary>
    public sealed class ZTNA21812 : ICippTest
    {
        private const string GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10";

        public string Id => "ZTNA21812";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var all = CippTestHelpers.RoleMembers(data, GlobalAdminRoleId);
            var globalAdmins = new List<DbRoleMember>();
            foreach (var m in all) if (m.IsUser || m.IsServicePrincipal) globalAdmins.Add(m);

            bool passed = globalAdmins.Count <= 5;

            var sb = new StringBuilder(passed
                ? "Maximum number of Global Administrators doesn't exceed five users/service principals.\n\n"
                : "Maximum number of Global Administrators exceeds five users/service principals.\n\n");

            if (globalAdmins.Count > 0)
            {
                sb.Append("## Global Administrators\n\n");
                sb.Append($"### Total number of Global Administrators: {globalAdmins.Count}\n\n");
                sb.Append("| Display Name | Object Type | User Principal Name |\n");
                sb.Append("| :----------- | :---------- | :------------------ |\n");
                foreach (var m in globalAdmins)
                {
                    string objectType = m.IsUser ? "User" : (m.IsServicePrincipal ? "Service Principal" : "Unknown");
                    string upn = string.IsNullOrEmpty(m.UserPrincipalName) ? "N/A" : m.UserPrincipalName!;
                    string link = m.IsUser
                        ? $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/{m.Id}"
                        : (m.IsServicePrincipal
                            ? $"https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/{m.Id}"
                            : "https://entra.microsoft.com");
                    sb.Append($"| [{m.DisplayName}]({link}) | {objectType} | {upn} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
