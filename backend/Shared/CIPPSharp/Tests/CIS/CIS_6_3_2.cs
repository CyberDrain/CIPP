using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (6.3.2) — The ability to add personal email accounts and calendars SHALL be disabled.
    /// Port of Invoke-CippTestCIS_6_3_2. Reads the default OWA mailbox policy; passes when both
    /// PersonalAccountsEnabled and PersonalAccountCalendarsEnabled are false.
    /// </summary>
    public sealed class CIS_6_3_2 : ICippTest
    {
        public string Id => "CIS_6_3_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("OwaMailboxPolicy"))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "OwaMailboxPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var d = PickOwaDefault(data)!.Value;

            if (IsFalse(d, "PersonalAccountsEnabled") && IsFalse(d, "PersonalAccountCalendarsEnabled"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Adding personal email accounts and calendars is disabled on '{Str(d, "Identity")}'.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Adding personal email accounts and/or calendars is not fully disabled on '{Str(d, "Identity")}' " +
                $"(PersonalAccountsEnabled: {Cell(Prop(d, "PersonalAccountsEnabled"))}, PersonalAccountCalendarsEnabled: {Cell(Prop(d, "PersonalAccountCalendarsEnabled"))}).");
        }
    }
}
