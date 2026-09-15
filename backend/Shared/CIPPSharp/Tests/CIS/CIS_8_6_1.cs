using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.6.1) — Users SHALL be able to report security concerns in Teams.
    /// Port of Invoke-CippTestCIS_8_6_1. Joins CsTeamsMessagingPolicy + ReportSubmissionPolicy; both
    /// caches are required. Passes when Teams end-user reporting is on AND Defender reporting routes
    /// junk/phish and chat-message reports.
    /// </summary>
    public sealed class CIS_8_6_1 : ICippTest
    {
        public string Id => "CIS_8_6_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var messaging = data.Get("CsTeamsMessagingPolicy");
            var submission = data.Get("ReportSubmissionPolicy");

            if (!Any(messaging) || !Any(submission))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (CsTeamsMessagingPolicy or ReportSubmissionPolicy) not found.");
            }

            var m = FirstOrNull(messaging)!.Value;
            var s = FirstOrNull(submission)!.Value;

            bool teamsReporting = IsTrue(m, "AllowSecurityEndUserReporting");
            bool defenderReporting =
                (IsTrue(s, "ReportJunkToCustomizedAddress") || IsTrue(s, "ReportPhishToCustomizedAddress"))
                && (IsTrue(s, "ReportChatMessageEnabled") || IsTrue(s, "ReportChatMessageToCustomizedAddressEnabled"));

            if (teamsReporting && defenderReporting)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Teams security reporting is enabled and routed to a monitored mailbox.\n\n" +
                    $"- AllowSecurityEndUserReporting: {Cell(Prop(m, "AllowSecurityEndUserReporting"))}\n" +
                    $"- ReportChatMessageEnabled: {Cell(Prop(s, "ReportChatMessageEnabled"))}\n" +
                    $"- ReportChatMessageToCustomizedAddressEnabled: {Cell(Prop(s, "ReportChatMessageToCustomizedAddressEnabled"))}");
            }

            return new CippTestResult(TestStatus.Failed,
                "Teams security reporting is not fully configured.\n\n" +
                $"- AllowSecurityEndUserReporting: {Cell(Prop(m, "AllowSecurityEndUserReporting"))}\n" +
                $"- ReportJunkToCustomizedAddress: {Cell(Prop(s, "ReportJunkToCustomizedAddress"))}\n" +
                $"- ReportPhishToCustomizedAddress: {Cell(Prop(s, "ReportPhishToCustomizedAddress"))}\n" +
                $"- ReportChatMessageEnabled: {Cell(Prop(s, "ReportChatMessageEnabled"))}\n" +
                $"- ReportChatMessageToCustomizedAddressEnabled: {Cell(Prop(s, "ReportChatMessageToCustomizedAddressEnabled"))}");
        }
    }
}
