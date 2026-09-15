using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Compliance policies protect personally owned Android devices.
    /// Port of Invoke-CippTestZTNA24547. @odata.type androidWorkProfileCompliancePolicy.
    /// </summary>
    public sealed class ZTNA24547 : ICippTest
    {
        public string Id => "ZTNA24547";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneDeviceCompliancePolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (StrEq(p, "@odata.type", "#microsoft.graph.androidWorkProfileCompliancePolicy")) matching.Add(p);

            bool passed = matching.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one compliance policy for Android Work Profile devices exists and is assigned.\n\n"
                : "❌ No compliance policy for Android Work Profile exists or none are assigned.\n\n");
            sb.Append("## Android Work Profile Compliance Policies\n\n");
            sb.Append("| Policy Name | Assigned |\n");
            sb.Append("| :---------- | :------- |\n");
            foreach (var p in matching)
                sb.Append($"| {Text(p, "displayName")} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
