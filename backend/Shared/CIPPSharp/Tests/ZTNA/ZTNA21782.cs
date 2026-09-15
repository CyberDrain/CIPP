using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Privileged accounts have phishing-resistant methods registered.
    /// Port of Invoke-CippTestZTNA21782. Joins UserRegistrationDetails to the privileged-role member
    /// set (role members + active PIM assignments), then checks each privileged user has a
    /// phishing-resistant method registered. Passed only when every privileged user does.
    /// </summary>
    public sealed class ZTNA21782 : ICippTest
    {
        private static readonly string[] PhishResistantMethods =
            { "passKeyDeviceBound", "passKeyDeviceBoundAuthenticator", "windowsHelloForBusiness" };

        private const string UserLinkFormat =
            "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/UserAuthMethods/userId/{0}/hidePreviewBanner~/true";

        public string Id => "ZTNA21782";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var userReg = data.Get("UserRegistrationDetails");
            var roles = PrivilegedRoles(data);
            var assignments = data.Get("RoleAssignmentScheduleInstances");

            if (!Any(userReg) || roles.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (UserRegistrationDetails or Roles) not found. Please refresh the cache for this tenant.");

            var privilegedRoleIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var roleNamesById = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var role in roles)
            {
                var tid = RoleTemplateId(role);
                if (!string.IsNullOrEmpty(tid))
                {
                    privilegedRoleIds.Add(tid!);
                    roleNamesById[tid!] = Str(role, "displayName") ?? "";
                }
            }

            var principals = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
            foreach (var role in roles)
            {
                var roleName = Str(role, "displayName") ?? "";
                foreach (var member in Arr(role, "members"))
                {
                    var pid = Str(member, "id");
                    if (string.IsNullOrEmpty(pid)) continue;
                    if (!principals.TryGetValue(pid!, out var set)) principals[pid!] = set = new HashSet<string>();
                    set.Add(roleName);
                }
            }

            foreach (var a in Items(assignments))
            {
                var rdId = Str(a, "roleDefinitionId");
                var endDate = Prop(a, "endDateTime");
                bool endNull = endDate.ValueKind == JsonValueKind.Null || endDate.ValueKind == JsonValueKind.Undefined;
                var pid = Str(a, "principalId");
                if (!string.IsNullOrEmpty(rdId) && StrEq(a, "assignmentType", "Assigned") && endNull
                    && privilegedRoleIds.Contains(rdId!) && !string.IsNullOrEmpty(pid))
                {
                    if (!principals.TryGetValue(pid!, out var set)) principals[pid!] = set = new HashSet<string>();
                    if (roleNamesById.TryGetValue(rdId!, out var rn) && !string.IsNullOrEmpty(rn)) set.Add(rn);
                }
            }

            var phishable = new List<(string Display, string Roles, string Id)>();
            var phishResistant = new List<(string Display, string Roles, string Id)>();
            int total = 0;

            foreach (var user in Items(userReg))
            {
                var uid = Str(user, "id");
                if (uid == null || !principals.TryGetValue(uid, out var userRoles)) continue;
                total++;

                bool hasPhish = false;
                foreach (var m in PhishResistantMethods)
                    if (ArrContains(user, "methodsRegistered", m)) { hasPhish = true; break; }

                var roleDisplay = string.Join(", ", userRoles.OrderBy(r => r, StringComparer.Ordinal));
                var entry = (Str(user, "userDisplayName") ?? "", roleDisplay, uid);
                if (hasPhish) phishResistant.Add(entry); else phishable.Add(entry);
            }

            bool passed = total == phishResistant.Count;

            var header = passed
                ? "Validated that all privileged users have registered phishing resistant authentication methods.\n\n"
                : "Found privileged users that have not yet registered phishing resistant authentication methods\n\n";

            var md = new StringBuilder(passed
                ? "All privileged users have registered phishing resistant authentication methods.\n\n"
                : "Found privileged users that have not registered phishing resistant authentication methods.\n\n");
            md.Append("| User | Role Name | Phishing resistant method registered |\n");
            md.Append("| :--- | :--- | :---: |\n");
            foreach (var e in phishable.OrderBy(x => x.Display, StringComparer.Ordinal))
                md.Append($"|[{e.Display}]({string.Format(UserLinkFormat, e.Id)})| {e.Roles} | ❌ |\n");
            foreach (var e in phishResistant.OrderBy(x => x.Display, StringComparer.Ordinal))
                md.Append($"|[{e.Display}]({string.Format(UserLinkFormat, e.Id)})| {e.Roles} | ✅ |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, header + md.ToString());
        }
    }
}
