using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (6.1.2) — Mailbox audit actions SHALL be configured.
    /// Port of Invoke-CippTestCIS_6_1_2. A user mailbox fails only when it has no owner audit actions
    /// (<c>@($_.AuditOwner).Count -eq 0</c>) AND its DefaultAuditSet does not list the Owner sign-in
    /// type. AuditEnabled itself (an EXO string boolean) is deliberately not graded.
    /// </summary>
    public sealed class CIS_6_1_2 : ICippTest
    {
        public string Id => "CIS_6_1_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mailboxes = data.Get("Mailboxes");
            if (!Any(mailboxes))
                return new CippTestResult(TestStatus.Skipped, "Mailboxes cache not found.");

            var userMailboxes = new List<JsonElement>();
            foreach (var m in mailboxes.EnumerateArray())
                if (StrEq(m, "RecipientTypeDetails", "UserMailbox")) userMailboxes.Add(m);

            int failures = 0;
            foreach (var m in userMailboxes)
            {
                if (PsArrayCount(m, "AuditOwner") == 0 && !MatchCI(PsStringify(m, "DefaultAuditSet"), "Owner"))
                    failures++;
            }

            if (failures == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {userMailboxes.Count} user mailbox(es) have owner audit actions configured.");

            return new CippTestResult(TestStatus.Failed,
                $"{failures} of {userMailboxes.Count} user mailbox(es) have no owner audit actions configured.");
        }
    }
}
