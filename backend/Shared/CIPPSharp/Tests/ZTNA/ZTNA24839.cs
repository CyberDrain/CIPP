using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Secure Wi-Fi profiles protect iOS devices from unauthorized network access.
    /// Port of Invoke-CippTestZTNA24839. iosWiFiConfiguration profiles; compliant security type is
    /// wpa2Enterprise or wpaEnterprise. Passed if a compliant profile is assigned. Table lists ALL
    /// iOS Wi-Fi profiles.
    /// </summary>
    public sealed class ZTNA24839 : ICippTest
    {
        public string Id => "ZTNA24839";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configs = data.Get("IntuneDeviceConfigurations");
            if (!Any(configs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var profiles = new List<JsonElement>();
            foreach (var c in Items(configs))
                if (StrEq(c, "@odata.type", "#microsoft.graph.iosWiFiConfiguration")) profiles.Add(c);

            int assignedCompliant = 0;
            foreach (var p in profiles)
                if (PropIn(p, "wiFiSecurityType", "wpa2Enterprise", "wpaEnterprise") && IsAssigned(p)) assignedCompliant++;

            bool passed = assignedCompliant > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one Enterprise Wi-Fi profile for iOS exists and is assigned.\n\n"
                : "❌ No Enterprise Wi-Fi profile for iOS exists or none are assigned.\n\n");

            if (profiles.Count > 0)
            {
                sb.Append("## iOS WiFi Configuration Profiles\n\n");
                sb.Append("| Policy Name | Wi-Fi Security Type | Assigned |\n");
                sb.Append("| :---------- | :------------------ | :------- |\n");
                foreach (var p in profiles)
                {
                    var sec = Str(p, "wiFiSecurityType") is string s && s.Length > 0 ? s : "Unknown";
                    sb.Append($"| {Text(p, "displayName")} | {sec} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");
                }
            }
            else
            {
                sb.Append("No iOS WiFi configuration profiles found.\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
