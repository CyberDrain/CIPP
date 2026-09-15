using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Limit the maximum number of devices per user to 10.
    /// Port of Invoke-CippTestZTNA21837. DeviceRegistrationPolicy.userDeviceQuota: null or ≤10 =
    /// Passed, 11-20 = Investigate (non-standard status passed through verbatim), &gt;20 = Failed.
    /// </summary>
    public sealed class ZTNA21837 : ICippTest
    {
        private const string Link =
            "https://entra.microsoft.com/#view/Microsoft_AAD_Devices/DevicesMenuBlade/~/DeviceSettings/menuId/Overview";

        public string Id => "ZTNA21837";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("DeviceRegistrationPolicy");
            if (!Any(settings))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement quotaEl = default;
            foreach (var rec in Items(settings)) { quotaEl = Prop(rec, "userDeviceQuota"); break; }

            bool isNull = quotaEl.ValueKind == JsonValueKind.Undefined || quotaEl.ValueKind == JsonValueKind.Null;
            double quota = 0;
            bool hasQuota = quotaEl.ValueKind == JsonValueKind.Number && quotaEl.TryGetDouble(out quota);
            string quotaText = isNull ? "" : Cell(quotaEl);

            if (isNull || (hasQuota && quota <= 10))
                return new CippTestResult(TestStatus.Passed,
                    $"[Maximum number of devices per user]({Link}) is set to {quotaText}");

            if (hasQuota && quota > 10 && quota <= 20)
                return new CippTestResult("Investigate",
                    $"[Maximum number of devices per user]({Link}) is set to {quotaText}. Consider reducing to 10 or fewer.");

            return new CippTestResult(TestStatus.Failed,
                $"[Maximum number of devices per user]({Link}) is set to {quotaText}. Consider reducing to 10 or fewer.");
        }
    }
}
