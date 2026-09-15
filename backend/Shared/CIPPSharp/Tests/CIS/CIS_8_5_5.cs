using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.5.5) — Meeting chat SHALL NOT allow anonymous users.
    /// Port of Invoke-CippTestCIS_8_5_5. Passes when MeetingChatEnabledType is
    /// EnabledExceptAnonymous or Disabled.
    /// </summary>
    public sealed class CIS_8_5_5 : ICippTest
    {
        public string Id => "CIS_8_5_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mp = data.Get("CsTeamsMeetingPolicy");
            if (!Any(mp))
            {
                return new CippTestResult(TestStatus.Skipped, "CsTeamsMeetingPolicy cache not found.");
            }

            var cfg = FirstOrNull(mp)!.Value;
            var chatType = Str(cfg, "MeetingChatEnabledType");

            if (InListCI(chatType, "EnabledExceptAnonymous", "Disabled"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Anonymous users cannot use meeting chat (MeetingChatEnabledType: {chatType}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Anonymous users can use meeting chat (MeetingChatEnabledType: {chatType}). Set to EnabledExceptAnonymous.");
        }
    }
}
