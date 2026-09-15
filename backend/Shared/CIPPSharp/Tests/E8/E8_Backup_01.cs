using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Regular Backups) — user mailboxes have litigation hold or a retention policy applied.
    /// Port of Invoke-CippTestE8_Backup_01. Reads Mailboxes (EXO string booleans honoured). The
    /// built-in "Default MRM Policy" does not count as a data-protection retention control.
    /// </summary>
    public sealed class E8_Backup_01 : ICippTest
    {
        public string Id => "E8_Backup_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mailboxes = data.Get("Mailboxes");
            if (!CippTestHelpers.Any(mailboxes))
            {
                return new CippTestResult(TestStatus.Skipped, "No Mailboxes cached for this tenant.");
            }

            var userMailboxes = CippTestHelpers.Items(mailboxes)
                .Where(m => CippTestHelpers.StrEq(m, "RecipientTypeDetails", "UserMailbox") && !Truthy(m, "WhenSoftDeleted"))
                .ToList();
            if (userMailboxes.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped, "No user mailboxes found.");
            }

            var unprotected = new List<JsonElement>();
            foreach (var m in userMailboxes)
            {
                if (CippTestHelpers.IsTrue(m, "LitigationHoldEnabled")) continue;
                if (CippTestHelpers.IsTrue(m, "ComplianceTagHoldApplied")) continue;
                var retention = CippTestHelpers.Str(m, "RetentionPolicy");
                var retentionUnprotected = string.IsNullOrWhiteSpace(retention)
                    || string.Equals(retention, "Default MRM Policy", StringComparison.OrdinalIgnoreCase);
                if (!retentionUnprotected) continue;
                if (Truthy(m, "InPlaceHolds")) continue;
                unprotected.Add(m);
            }

            if (unprotected.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {userMailboxes.Count} user mailbox(es) have at least one of: litigation hold, a non-default retention policy, or compliance hold applied.");
            }

            var sb = new StringBuilder();
            sb.Append($"{unprotected.Count} of {userMailboxes.Count} user mailbox(es) have no litigation hold, retention policy, or compliance tag applied:\n\n");
            var rows = unprotected.Take(50).Select(m => (IReadOnlyList<string>)new[] { CippTestHelpers.Str(m, "UPN") ?? "" });
            sb.Append(Markdown.Table(new[] { "UPN" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        private static bool Truthy(JsonElement el, string name)
            => CippTestHelpers.TryProp(el, name, out var v) && CippTestHelpers.Truthy(v);
    }
}
