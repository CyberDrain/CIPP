using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.4) — All member users SHALL be 'MFA capable'.
    /// Port of Invoke-CippTestCIS_5_2_3_4. Joins UserRegistrationDetails to enabled member Users (by
    /// id, falling back to UPN) and flags any without isMfaCapable.
    /// </summary>
    public sealed class CIS_5_2_3_4 : ICippTest
    {
        public string Id => "CIS_5_2_3_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var reg = data.Get("UserRegistrationDetails");
            var users = data.Get("Users");

            if (!Any(reg) || !Any(users))
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (UserRegistrationDetails or Users) not found.");

            var members = new List<JsonElement>();
            foreach (var u in users.EnumerateArray())
                if (StrEq(u, "userType", "Member") && IsTrue(u, "accountEnabled")) members.Add(u);

            var regById = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            var regByUpn = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var r in reg.EnumerateArray())
            {
                var id = Str(r, "id");
                if (!string.IsNullOrEmpty(id)) regById[id!] = r;
                var upn = Str(r, "userPrincipalName");
                if (!string.IsNullOrEmpty(upn)) regByUpn[upn!] = r;
            }

            var notCapable = new List<JsonElement>();
            foreach (var u in members)
            {
                JsonElement? r = null;
                var id = Str(u, "id");
                var upn = Str(u, "userPrincipalName");
                if (!string.IsNullOrEmpty(id) && regById.TryGetValue(id!, out var byId)) r = byId;
                else if (!string.IsNullOrEmpty(upn) && regByUpn.TryGetValue(upn!, out var byUpn)) r = byUpn;

                if (r == null || !IsTrue(r.Value, "isMfaCapable")) notCapable.Add(u);
            }

            if (notCapable.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {members.Count} enabled member users are MFA capable.");

            var sb = new StringBuilder();
            sb.Append($"{notCapable.Count} of {members.Count} enabled member user(s) are not MFA capable.\n\n");
            var lines = new List<string>();
            int shown = 0;
            foreach (var u in notCapable)
            {
                if (shown++ >= 25) break;
                lines.Add($"- {Str(u, "userPrincipalName")}");
            }
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
