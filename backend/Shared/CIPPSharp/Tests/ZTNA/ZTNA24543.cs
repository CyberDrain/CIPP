using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Compliance policies protect iOS/iPadOS devices.
    /// Port of Invoke-CippTestZTNA24543. iOS compliance policy = @odata.type iosCompliancePolicy.
    /// </summary>
    public sealed class ZTNA24543 : ICippTest
    {
        public string Id => "ZTNA24543";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneDeviceCompliancePolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (StrEq(p, "@odata.type", "#microsoft.graph.iosCompliancePolicy")) matching.Add(p);

            bool passed = matching.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one iOS/iPadOS compliance policy exists and is assigned.\n\n"
                : "❌ No iOS/iPadOS compliance policy exists or none are assigned.\n\n");
            sb.Append("## iOS/iPadOS Compliance Policies\n\n");
            sb.Append("| Policy Name | Assigned |\n");
            sb.Append("| :---------- | :------- |\n");
            foreach (var p in matching)
                sb.Append($"| {Text(p, "displayName")} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
