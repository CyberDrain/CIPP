using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Compliance policies protect Windows devices.
    /// Port of Invoke-CippTestZTNA24541. Windows compliance policy = @odata.type is win10/win11
    /// compliance policy; Passed if at least one is assigned.
    /// </summary>
    public sealed class ZTNA24541 : ICippTest
    {
        public string Id => "ZTNA24541";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneDeviceCompliancePolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new System.Collections.Generic.List<System.Text.Json.JsonElement>();
            foreach (var p in Items(policies))
                if (PropIn(p, "@odata.type", "#microsoft.graph.windows10CompliancePolicy", "#microsoft.graph.windows11CompliancePolicy"))
                    matching.Add(p);

            bool passed = matching.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one Windows compliance policy exists and is assigned.\n\n"
                : "❌ No Windows compliance policy exists or none are assigned.\n\n");
            sb.Append("## Windows Compliance Policies\n\n");
            sb.Append("| Policy Name | Assigned |\n");
            sb.Append("| :---------- | :------- |\n");
            foreach (var p in matching)
                sb.Append($"| {Text(p, "displayName")} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
