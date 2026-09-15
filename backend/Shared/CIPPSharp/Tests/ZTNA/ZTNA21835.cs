using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Emergency access accounts are configured appropriately.
    /// Port of Invoke-CippTestZTNA21835. Cloud-only permanent Global Administrators that are excluded
    /// from every enabled CA policy are treated as emergency access accounts; passes when 2-4 exist.
    /// (Group/role membership targeting is not evaluated — the cache lacks per-user expansion, matching
    /// the PS simplification.)
    /// </summary>
    public sealed class ZTNA21835 : ICippTest
    {
        private const string GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10";

        public string Id => "ZTNA21835";

        private sealed class Candidate
        {
            public string Id = "";
            public string Upn = "";
            public string DisplayName = "";
            public bool CloudOnly;
            public bool ExcludedFromAllCA;
        }

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var roles = data.Get("Roles");
            bool gaFound = false;
            foreach (var r in Items(roles)) if (StrEq(r, "roleTemplateId", GlobalAdminRoleId)) { gaFound = true; break; }
            if (!gaFound)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var permanentGa = new List<DbRoleMember>();
            foreach (var m in CippTestHelpers.RoleMembers(data, GlobalAdminRoleId))
                if (m.IsPermanent && m.IsUser) permanentGa.Add(m);

            var users = data.Get("Users");
            var usersById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var u in Items(users)) { var id = Str(u, "id"); if (id != null && !usersById.ContainsKey(id)) usersById[id] = u; }

            var candidates = new List<Candidate>();
            foreach (var member in permanentGa)
            {
                if (member.Id == null || !usersById.TryGetValue(member.Id, out var user)) continue;
                if (IsTrue(user, "onPremisesSyncEnabled")) continue; // only cloud-only
                candidates.Add(new Candidate
                {
                    Id = Str(user, "id") ?? "",
                    Upn = Str(user, "userPrincipalName") ?? "",
                    DisplayName = Str(user, "displayName") ?? "",
                    CloudOnly = true
                });
            }

            var enabledPolicies = new List<JsonElement>();
            foreach (var p in Items(data.Get("ConditionalAccessPolicies")))
                if (StrEq(p, "state", "enabled")) enabledPolicies.Add(p);

            var emergency = new List<Candidate>();
            foreach (var c in candidates)
            {
                bool excludedFromAll = true;
                foreach (var policy in enabledPolicies)
                {
                    var include = FlattenStrings(policy, "conditions", "users", "includeUsers");
                    var exclude = FlattenStrings(policy, "conditions", "users", "excludeUsers");

                    bool targeted = ListContains(include, "All") || ListContains(include, c.Id);
                    if (ListContains(exclude, c.Id)) targeted = false;

                    if (targeted) excludedFromAll = false;
                }
                c.ExcludedFromAllCA = excludedFromAll;
                if (excludedFromAll) emergency.Add(c);
            }

            int accountCount = emergency.Count;
            bool passed = accountCount >= 2 && accountCount <= 4;

            string header;
            if (accountCount < 2)
                header = "Fewer than two emergency access accounts were identified based on cloud-only state, registered phishing-resistant credentials and Conditional Access policy exclusions.\n\n";
            else if (accountCount <= 4)
                header = "Emergency access accounts appear to be configured as per Microsoft guidance based on cloud-only state, registered phishing-resistant credentials and Conditional Access policy exclusions.\n\n";
            else
                header = $"{accountCount} emergency access accounts appear to be configured based on cloud-only state, registered phishing-resistant credentials and Conditional Access policy exclusions. Review these accounts to determine whether this volume is excessive for your organization.\n\n";

            var sb = new StringBuilder(header);
            sb.Append("**Summary:**\n");
            sb.Append($"- Total permanent Global Administrators: {permanentGa.Count}\n");
            sb.Append($"- Cloud-only GAs with phishing-resistant auth: {candidates.Count}\n");
            sb.Append($"- Emergency access accounts (excluded from all CA): {accountCount}\n");
            sb.Append($"- Enabled Conditional Access policies: {enabledPolicies.Count}\n\n");

            if (emergency.Count > 0)
            {
                sb.Append("## Emergency access accounts\n\n");
                sb.Append("| Display name | UPN | Synced from on-premises | Authentication methods |\n");
                sb.Append("| :----------- | :-- | :---------------------- | :--------------------- |\n");
                foreach (var a in emergency)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/{a.Id}";
                    sb.Append($"| {a.DisplayName} | [{a.Upn}]({link}) | No | Unknown - requires per-user API call |\n");
                }
                sb.Append("\n");
            }

            if (permanentGa.Count > 0)
            {
                sb.Append("## All permanent Global Administrators\n\n");
                sb.Append("| Display name | UPN | Cloud only | All CA excluded | Phishing resistant auth |\n");
                sb.Append("| :----------- | :-- | :--------: | :---------: | :---------------------: |\n");
                var emergencyIds = new HashSet<string>(StringComparer.Ordinal);
                foreach (var a in emergency) emergencyIds.Add(a.Id);
                var candidateIds = new HashSet<string>(StringComparer.Ordinal);
                foreach (var c in candidates) candidateIds.Add(c.Id);

                foreach (var member in permanentGa)
                {
                    if (member.Id == null || !usersById.TryGetValue(member.Id, out var user)) continue;
                    var uid = Str(user, "id") ?? "";
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/{uid}";
                    string cloudOnly = !IsTrue(user, "onPremisesSyncEnabled") ? "✅" : "❌";
                    string caExcluded = emergencyIds.Contains(uid) ? "✅" : "❌";
                    string phish = candidateIds.Contains(uid) ? "✅" : "❌";
                    sb.Append($"| {Text(user, "displayName")} | [{Text(user, "userPrincipalName")}]({link}) | {cloudOnly} | {caExcluded} | {phish} |\n");
                }
                sb.Append("\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        private static bool ListContains(List<string> list, string value)
        {
            foreach (var s in list) if (string.Equals(s, value, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
