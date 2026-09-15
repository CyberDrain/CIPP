using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.5.3) — Only people in my org SHALL be able to bypass the lobby.
    /// Port of Invoke-CippTestCIS_8_5_3. Passes when AutoAdmittedUsers is one of
    /// OrganizerOnly / EveryoneInCompanyExcludingGuests / InvitedUsers.
    /// </summary>
    public sealed class CIS_8_5_3 : ICippTest
    {
        public string Id => "CIS_8_5_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mp = data.Get("CsTeamsMeetingPolicy");
            if (!Any(mp))
            {
                return new CippTestResult(TestStatus.Skipped, "CsTeamsMeetingPolicy cache not found.");
            }

            var cfg = FirstOrNull(mp)!.Value;
            var auto = Str(cfg, "AutoAdmittedUsers");

            if (InListCI(auto, "OrganizerOnly", "EveryoneInCompanyExcludingGuests", "InvitedUsers"))
            {
                return new CippTestResult(TestStatus.Passed, $"Lobby bypass restricted (AutoAdmittedUsers: {auto}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Lobby bypass too permissive (AutoAdmittedUsers: {auto}). Set to EveryoneInCompanyExcludingGuests or stricter.");
        }
    }
}
