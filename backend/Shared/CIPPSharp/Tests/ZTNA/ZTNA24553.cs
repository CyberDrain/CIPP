using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Windows Update policies are enforced to reduce risk from unpatched vulnerabilities.
    /// Port of Invoke-CippTestZTNA24553. IntuneDeviceCompliancePolicies of type
    /// windowsUpdateForBusinessConfiguration or windows10CompliancePolicy; Passed if any assigned.
    /// </summary>
    public sealed class ZTNA24553 : ICippTest
    {
        public string Id => "ZTNA24553";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneDeviceCompliancePolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (PropIn(p, "@odata.type", "#microsoft.graph.windowsUpdateForBusinessConfiguration", "#microsoft.graph.windows10CompliancePolicy"))
                    matching.Add(p);

            bool passed = matching.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ Windows Update policies are configured and assigned.\n\n"
                : "❌ No Windows Update policies are configured or assigned.\n\n");
            sb.Append("## Windows Update Policies\n\n");
            sb.Append("| Policy Name | Type | Assigned |\n");
            sb.Append("| :---------- | :--- | :------- |\n");
            foreach (var p in matching)
            {
                var type = StrEq(p, "@odata.type", "#microsoft.graph.windowsUpdateForBusinessConfiguration") ? "Update" : "Compliance";
                sb.Append($"| {Text(p, "displayName")} | {type} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
