using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Patch Operating Systems) — a device compliance policy enforces a minimum Windows OS
    /// version. Port of Invoke-CippTestE8_PatchOS_03. Reads IntuneDeviceCompliancePolicies.
    /// </summary>
    public sealed class E8_PatchOS_03 : ICippTest
    {
        public string Id => "E8_PatchOS_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var compliance = data.Get("IntuneDeviceCompliancePolicies");
            if (!CippTestHelpers.Any(compliance))
            {
                return new CippTestResult(TestStatus.Skipped, "No Intune compliance policies cached for this tenant.");
            }

            var win = CippTestHelpers.Items(compliance)
                .Where(p => CippTestHelpers.StrEq(p, "@odata.type", "#microsoft.graph.windows10CompliancePolicy"))
                .ToList();
            var withMinVersion = win.Where(p => CippTestHelpers.HasText(p, "osMinimumVersion")).ToList();
            var assigned = withMinVersion.Where(CippTestHelpers.HasAssignments).ToList();

            if (assigned.Count > 0)
            {
                var first = CippTestHelpers.Str(assigned[0], "osMinimumVersion");
                return new CippTestResult(TestStatus.Passed,
                    $"{assigned.Count} Windows compliance policy/policies enforce a minimum OS version (e.g. {first}).");
            }
            if (withMinVersion.Count > 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"{withMinVersion.Count} Windows compliance policy/policies set a minimum OS version but none are assigned.");
            }
            return new CippTestResult(TestStatus.Failed,
                "No Windows compliance policy enforces a minimum OS version (`osMinimumVersion`).");
        }
    }
}
