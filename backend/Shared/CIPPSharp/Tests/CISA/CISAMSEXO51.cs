using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.5.1 — SMTP AUTH SHALL be disabled for all users.
    /// Port of Invoke-CippTestCISAMSEXO51. Fails CAS mailboxes where
    /// <c>SmtpClientAuthenticationDisabled -eq $false</c>; renders the first 10 offenders.
    /// </summary>
    public sealed class CISAMSEXO51 : ICippTest
    {
        public string Id => "CISAMSEXO51";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mailboxes = data.Get("CASMailbox");
            if (!Any(mailboxes))
                return new CippTestResult(TestStatus.Skipped,
                    "CASMailbox cache not found. Please refresh the cache for this tenant.");

            var failed = new List<JsonElement>();
            int total = 0;
            foreach (var m in Items(mailboxes))
            {
                total++;
                if (EqFalse(m, "SmtpClientAuthenticationDisabled")) failed.Add(m);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: SMTP authentication is disabled for all {total} mailbox(es).");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} mailbox(es) have SMTP authentication enabled");
            if (failed.Count > 10) sb.Append(" (showing first 10)");
            sb.Append(":\n\n");
            sb.Append("| Display Name | Identity | SMTP Auth Disabled |\n");
            sb.Append("| :----------- | :------- | :----------------- |\n");
            int shown = 0;
            foreach (var m in failed)
            {
                if (shown++ >= 10) break;
                sb.Append($"| {Cell(m, "DisplayName")} | {Cell(m, "Identity")} | {Cell(m, "SmtpClientAuthenticationDisabled")} |\n");
            }
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
