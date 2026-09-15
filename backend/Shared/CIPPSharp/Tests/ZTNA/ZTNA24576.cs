using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Endpoint Analytics is enabled to help identify risks on Windows devices.
    /// Port of Invoke-CippTestZTNA24576. IntuneDeviceConfigurations of type
    /// windowsHealthMonitoringConfiguration; Passed if any assigned.
    /// </summary>
    public sealed class ZTNA24576 : ICippTest
    {
        public string Id => "ZTNA24576";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configs = data.Get("IntuneDeviceConfigurations");
            if (!Any(configs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new List<JsonElement>();
            foreach (var c in Items(configs))
                if (StrEq(c, "@odata.type", "#microsoft.graph.windowsHealthMonitoringConfiguration")) matching.Add(c);

            bool passed = matching.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ An Endpoint analytics policy is created and assigned.\n\n"
                : "❌ Endpoint analytics policy is not created or not assigned.\n\n");

            if (matching.Count > 0)
            {
                sb.Append("## Endpoint Analytics Policies\n\n");
                sb.Append("| Policy Name | Assigned |\n");
                sb.Append("| :---------- | :------- |\n");
                foreach (var p in matching)
                    sb.Append($"| {Text(p, "displayName")} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");
            }
            else
            {
                sb.Append("No Endpoint Analytics policies found in this tenant.\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
