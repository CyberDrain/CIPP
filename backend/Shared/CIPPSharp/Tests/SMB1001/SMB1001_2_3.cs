using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.3) — Individual user accounts: shared/resource mailboxes must not have an
    /// enabled, cloud-only Entra account. Port of Invoke-CippTestSMB1001_2_3. Joins Mailboxes +
    /// Users (by ExternalDirectoryObjectId==id or UPN==userPrincipalName).
    /// </summary>
    public sealed class SMB1001_2_3 : ICippTest
    {
        private static readonly string[] SharedTypes =
            { "SharedMailbox", "SchedulingMailbox", "EquipmentMailbox", "RoomMailbox" };

        public string Id => "SMB1001_2_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mailboxes = data.Get("Mailboxes");
            var users = data.Get("Users");

            if (!Any(mailboxes) || !Any(users))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Mailboxes or Users) not found. Please refresh the cache for this tenant.");
            }

            var byId = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            var byUpn = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            foreach (var u in Items(users))
            {
                var id = Str(u, "id");
                if (!string.IsNullOrEmpty(id) && !byId.ContainsKey(id!)) byId[id!] = u;
                var upn = Str(u, "userPrincipalName");
                if (!string.IsNullOrEmpty(upn) && !byUpn.ContainsKey(upn!)) byUpn[upn!] = u;
            }

            var shared = new List<JsonElement>();
            foreach (var m in Items(mailboxes))
            {
                var type = Str(m, "recipientTypeDetails");
                if (type != null && Array.Exists(SharedTypes, t => string.Equals(t, type, StringComparison.OrdinalIgnoreCase)))
                    shared.Add(m);
            }

            var enabledShared = new List<(string upn, string type)>();
            foreach (var m in shared)
            {
                JsonElement user = default;
                var extId = Str(m, "ExternalDirectoryObjectId");
                var mbxUpn = Str(m, "UPN");
                if (!string.IsNullOrEmpty(extId) && byId.TryGetValue(extId!, out var byIdUser)) user = byIdUser;
                else if (!string.IsNullOrEmpty(mbxUpn) && byUpn.TryGetValue(mbxUpn!, out var byUpnUser)) user = byUpnUser;

                if (user.ValueKind == JsonValueKind.Object
                    && IsTrue(user, "accountEnabled")
                    && !IsTrue(user, "onPremisesSyncEnabled"))
                {
                    enabledShared.Add((mbxUpn ?? "", Str(m, "recipientTypeDetails") ?? ""));
                }
            }

            if (shared.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "No shared, scheduling, room, or equipment mailboxes exist in the tenant.");
            }

            if (enabledShared.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {shared.Count} shared/resource mailbox account(s) have sign-in disabled. Employees access them via delegation only.");
            }

            var sb = new StringBuilder();
            sb.Append($"{enabledShared.Count} of {shared.Count} shared/resource mailbox(es) still have an enabled Entra account that could be logged into with shared credentials:\n\n");
            var rows = new List<IReadOnlyList<string>>();
            int shown = 0;
            foreach (var e in enabledShared)
            {
                if (shown++ >= 25) break;
                rows.Add(new[] { e.upn, e.type });
            }
            sb.Append(Markdown.Table(new[] { "Mailbox", "Type" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
        }
    }
}
