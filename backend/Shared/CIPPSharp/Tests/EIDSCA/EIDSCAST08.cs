using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Classification and M365 Groups - Allow Guests to become Group Owner. Port of Invoke-CippTestEIDSCAST08. Source: Settings.</summary>
    public sealed class EIDSCAST08 : ICippTest
    {
        public string Id => "EIDSCAST08";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "AllowGuestsToBeGroupOwner");
            if (StrIn(value, "false"))
                return new CippTestResult(TestStatus.Passed, "Guests are not allowed to become group owners");

            var result = $@"Guests should not be allowed to become group owners to maintain proper access control.

**Current Configuration:**
- AllowGuestsToBeGroupOwner: {value}

**Recommended Configuration:**
- AllowGuestsToBeGroupOwner: false";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
