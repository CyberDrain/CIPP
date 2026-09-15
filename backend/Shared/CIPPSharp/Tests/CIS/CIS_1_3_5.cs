using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.3.5) — Internal phishing protection for Forms SHALL be enabled.
    /// Port of Invoke-CippTestCIS_1_3_5. Reads FormsSettings (falls back to a Settings record).
    /// </summary>
    public sealed class CIS_1_3_5 : ICippTest
    {
        public string Id => "CIS_1_3_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            JsonElement? forms = FirstOrNull(data.Get("FormsSettings"));
            if (forms == null)
            {
                foreach (var s in Items(data.Get("Settings")))
                {
                    if (TryProp(s, "isInOrgFormsPhishingScanEnabled", out _))
                    {
                        forms = s;
                        break;
                    }
                }
            }

            if (forms == null)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Forms phishing scan setting not in cache. Please refresh FormsSettings cache for this tenant.");
            }

            if (IsTrue(forms.Value, "isInOrgFormsPhishingScanEnabled"))
            {
                return new CippTestResult(TestStatus.Passed, "Internal Forms phishing scan is enabled.");
            }

            var cell = Cell(Prop(forms.Value, "isInOrgFormsPhishingScanEnabled"));
            return new CippTestResult(TestStatus.Failed,
                $"Forms phishing scan is disabled (isInOrgFormsPhishingScanEnabled: {cell}).");
        }
    }
}
