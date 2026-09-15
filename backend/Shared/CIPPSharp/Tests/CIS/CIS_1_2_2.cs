using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.2.2) — Sign-in to shared mailboxes SHALL be blocked.
    /// Port of Invoke-CippTestCIS_1_2_2. Joins shared Mailboxes to Users (by UPN, then by
    /// ExternalDirectoryObjectId) and flags any with an enabled account.
    /// </summary>
    public sealed class CIS_1_2_2 : ICippTest
    {
        public string Id => "CIS_1_2_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mailboxes = data.Get("Mailboxes");
            var users = data.Get("Users");

            if (!Any(mailboxes) || !Any(users))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Mailboxes or Users) not found. Please refresh the cache for this tenant.");
            }

            var sharedMailboxes = new List<JsonElement>();
            foreach (var m in mailboxes.EnumerateArray())
                if (StrEq(m, "RecipientTypeDetails", "SharedMailbox")) sharedMailboxes.Add(m);

            if (sharedMailboxes.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No shared mailboxes found.");

            // PowerShell hashtables are case-insensitive keyed.
            var usersById = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            var usersByUpn = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var u in users.EnumerateArray())
            {
                var id = Str(u, "id");
                if (!string.IsNullOrEmpty(id)) usersById[id!] = u;
                var upn = Str(u, "userPrincipalName");
                if (!string.IsNullOrEmpty(upn)) usersByUpn[upn!] = u;
            }

            var enabledShared = new List<JsonElement>();
            foreach (var sm in sharedMailboxes)
            {
                JsonElement? user = null;
                var smUpn = Str(sm, "UserPrincipalName");
                var smExt = Str(sm, "ExternalDirectoryObjectId");
                if (!string.IsNullOrEmpty(smUpn) && usersByUpn.TryGetValue(smUpn!, out var byUpn)) user = byUpn;
                else if (!string.IsNullOrEmpty(smExt) && usersById.TryGetValue(smExt!, out var byId)) user = byId;

                if (user != null && IsTrue(user.Value, "accountEnabled"))
                    enabledShared.Add(user.Value);
            }

            if (enabledShared.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {sharedMailboxes.Count} shared mailbox account(s) have sign-in blocked.");
            }

            var sb = new StringBuilder();
            sb.Append($"{enabledShared.Count} of {sharedMailboxes.Count} shared mailbox(es) have sign-in enabled:\n\n");
            var lines = new List<string>();
            int shown = 0;
            foreach (var u in enabledShared)
            {
                if (shown++ >= 25) break;
                lines.Add($"- {Str(u, "userPrincipalName")}");
            }
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
