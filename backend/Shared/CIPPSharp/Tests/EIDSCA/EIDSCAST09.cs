using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>Classification and M365 Groups - Allow Guests to have access to groups content. Port of Invoke-CippTestEIDSCAST09. Source: Settings.</summary>
    public sealed class EIDSCAST09 : ICippTest
    {
        public string Id => "EIDSCAST09";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings)) return new CippTestResult(TestStatus.Skipped, SkipMessage);

            var value = SettingValue(settings, "AllowGuestsToAccessGroups");
            if (StrIn(value, "True"))
                return new CippTestResult(TestStatus.Passed, "Guests are allowed to access groups content");

            var result = $@"Guests should be allowed to access groups content for proper collaboration.

**Current Configuration:**
- AllowGuestsToAccessGroups: {value}

**Recommended Configuration:**
- AllowGuestsToAccessGroups: True";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
