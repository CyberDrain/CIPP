using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.3.7) — 'Third-party storage services' SHALL be restricted in 'Microsoft 365 on
    /// the web'. Port of Invoke-CippTestCIS_1_3_7. Checks the "Microsoft 365 on the web" service
    /// principal is absent or disabled.
    /// </summary>
    public sealed class CIS_1_3_7 : ICippTest
    {
        private const string AppId = "c1f33bc0-bdb4-4248-ba9b-096807ddb43e";

        public string Id => "CIS_1_3_7";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var sps = data.Get("ServicePrincipals");
            if (!Any(sps))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ServicePrincipals cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? sp = null;
            foreach (var s in sps.EnumerateArray())
                if (StrEq(s, "appId", AppId)) { sp = s; break; }

            if (sp == null)
            {
                return new CippTestResult(TestStatus.Passed,
                    "The Microsoft 365 on the web service principal is not present in the tenant — third-party storage cannot be enabled.");
            }

            if (IsFalse(sp.Value, "accountEnabled"))
            {
                var cell = Cell(Prop(sp.Value, "accountEnabled"));
                return new CippTestResult(TestStatus.Passed,
                    $"The Microsoft 365 on the web service principal exists but is disabled (accountEnabled: {cell}).");
            }

            return new CippTestResult(TestStatus.Failed,
                "The Microsoft 365 on the web service principal is enabled. Disable it to restrict third-party storage providers.");
        }
    }
}
