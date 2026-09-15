using System.Collections.Generic;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (3.1) — Backup/recovery: Litigation Hold enabled on licence-eligible user
    /// mailboxes. Port of Invoke-CippTestSMB1001_3_1. Single source: Mailboxes.
    /// </summary>
    public sealed class SMB1001_3_1 : ICippTest
    {
        public string Id => "SMB1001_3_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mailboxes = data.Get("Mailboxes");
            if (!Any(mailboxes))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Mailboxes cache not found. Please refresh the cache for this tenant.");
            }

            var eligible = new List<System.Text.Json.JsonElement>();
            foreach (var m in Items(mailboxes))
                if (StrEq(m, "recipientTypeDetails", "UserMailbox") && IsTrue(m, "LicensedForLitigationHold"))
                    eligible.Add(m);

            var withoutHold = new List<System.Text.Json.JsonElement>();
            foreach (var m in eligible)
                if (!IsTrue(m, "LitigationHoldEnabled")) withoutHold.Add(m);

            if (eligible.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No user mailboxes with a licence that supports Litigation Hold were found. SMB1001 (3.1) still requires an offline-isolated backup strategy — evidence the third-party backup product separately.");
            }

            if (withoutHold.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Litigation Hold is enabled on all {eligible.Count} eligible user mailbox(es). Evidence the offline-isolated backup half of SMB1001 (3.1) separately (e.g., third-party M365 backup vendor).");
            }

            var sb = new StringBuilder();
            sb.Append($"{withoutHold.Count} of {eligible.Count} eligible user mailbox(es) do not have Litigation Hold enabled. Without preservation, deleted email cannot be recovered after the retention window:\n\n");
            int shown = 0;
            var lines = new List<string>();
            foreach (var m in withoutHold)
            {
                if (shown++ >= 25) break;
                lines.Add($"- {Str(m, "UPN") ?? ""}");
            }
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
