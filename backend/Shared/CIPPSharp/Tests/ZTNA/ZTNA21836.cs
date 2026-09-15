using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Workload Identities are not assigned privileged roles.
    /// Port of Invoke-CippTestZTNA21836. Fails if any service principal is a member of a privileged role.
    /// </summary>
    public sealed class ZTNA21836 : ICippTest
    {
        public string Id => "ZTNA21836";

        private sealed class Row
        {
            public string PrincipalId = "";
            public string PrincipalDisplayName = "";
            public string AppId = "";
            public string RoleDisplayName = "";
            public string AssignmentType = "";
        }

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            if (privilegedRoles.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var workload = new List<Row>();
            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null) continue;
                var roleName = Str(role, "displayName") ?? "";
                foreach (var member in CippTestHelpers.RoleMembers(data, tid))
                {
                    if (!member.IsServicePrincipal) continue;
                    workload.Add(new Row
                    {
                        PrincipalId = member.Id ?? "",
                        PrincipalDisplayName = member.DisplayName ?? "",
                        AppId = member.AppId ?? "",
                        RoleDisplayName = roleName,
                        AssignmentType = member.AssignmentType
                    });
                }
            }

            if (workload.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **No workload identities found with privileged role assignments.**\n");

            var sb = new StringBuilder("**Found workload identities assigned to privileged roles.**\n");
            sb.Append("| Service Principal Name | Privileged Role | Assignment Type |\n");
            sb.Append("| :--- | :--- | :--- |\n");
            foreach (var a in workload.OrderBy(x => x.PrincipalDisplayName, System.StringComparer.Ordinal))
            {
                var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/{a.PrincipalId}/appId/{a.AppId}";
                sb.Append($"| [{a.PrincipalDisplayName}]({link}) | {a.RoleDisplayName} | {a.AssignmentType} |\n");
            }
            sb.Append("\n");
            sb.Append("\n**Recommendation:** Review and remove privileged role assignments from workload identities unless absolutely necessary. Use least-privilege principles and consider alternative approaches like managed identities with specific API permissions instead of directory roles.\n");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
