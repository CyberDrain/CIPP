using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Secure Wi-Fi profiles protect Android devices from unauthorized network access.
    /// Port of Invoke-CippTestZTNA24840. androidDeviceOwnerEnterpriseWiFiConfiguration profiles with
    /// wiFiSecurityType == wpaEnterprise. Passed if a compliant profile is assigned. Table lists the
    /// compliant profiles.
    /// </summary>
    public sealed class ZTNA24840 : ICippTest
    {
        public string Id => "ZTNA24840";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configs = data.Get("IntuneDeviceConfigurations");
            if (!Any(configs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var compliant = new List<JsonElement>();
            foreach (var c in Items(configs))
                if (StrEq(c, "@odata.type", "#microsoft.graph.androidDeviceOwnerEnterpriseWiFiConfiguration")
                    && StrEq(c, "wiFiSecurityType", "wpaEnterprise"))
                    compliant.Add(c);

            bool passed = compliant.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one Enterprise Wi-Fi profile for android exists and is assigned.\n\n"
                : "❌ No Enterprise Wi-Fi profile for android exists or none are assigned.\n\n");

            if (compliant.Count > 0)
            {
                sb.Append("## Android Wi-Fi Configuration Profiles\n\n");
                sb.Append("| Policy Name | Wi-Fi Security Type | Assigned |\n");
                sb.Append("| :---------- | :------------------ | :------- |\n");
                foreach (var p in compliant)
                {
                    var sec = Str(p, "wiFiSecurityType") is string s && s.Length > 0 ? s : "Unknown";
                    sb.Append($"| {Text(p, "displayName")} | {sec} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");
                }
            }
            else
            {
                sb.Append("No compliant Android Enterprise WiFi configuration profiles found.\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
