using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (Patch Operating Systems) — a compliance policy requires storage encryption
    /// (BitLocker). Port of Invoke-CippTestE8_PatchOS_06. Reads IntuneDeviceCompliancePolicies.
    /// </summary>
    public sealed class E8_PatchOS_06 : ICippTest
    {
        public string Id => "E8_PatchOS_06";

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
            var withEnc = win
                .Where(p => CippTestHelpers.IsTrue(p, "bitLockerEnabled") || CippTestHelpers.IsTrue(p, "storageRequireEncryption"))
                .ToList();
            var assigned = withEnc.Where(CippTestHelpers.HasAssignments).ToList();

            if (assigned.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{assigned.Count} Windows compliance policy/policies require encryption (BitLocker) and are assigned.");
            }
            if (withEnc.Count > 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"Encryption is required by {withEnc.Count} compliance policy/policies but none are assigned.");
            }
            return new CippTestResult(TestStatus.Failed,
                "No Windows compliance policy requires storage encryption / BitLocker.");
        }
    }
}
