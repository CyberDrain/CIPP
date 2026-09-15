using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.2) — Employees lack local admin: registering users are not auto-granted local
    /// admin, and an assigned Windows LAPS policy manages the local admin credential. Port of
    /// Invoke-CippTestSMB1001_2_2. Two sources: DeviceRegistrationPolicy + IntuneConfigurationPolicies.
    /// </summary>
    public sealed class SMB1001_2_2 : ICippTest
    {
        private const string NoMembershipType = "#microsoft.graph.noDeviceRegistrationMembership";
        private const string LapsDefId = "device_vendor_msft_laps_policies_backupdirectory";

        public string Id => "SMB1001_2_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var deviceReg = data.Get("DeviceRegistrationPolicy");
            var configPolicies = data.Get("IntuneConfigurationPolicies");
            var issues = new List<string>();

            // 1. Device registration policy: registering users should NOT auto become local admin.
            if (Any(deviceReg))
            {
                var cfg = First(deviceReg);
                var registeringType = Str(
                    Prop(Prop(Prop(cfg, "azureADJoin"), "localAdmins"), "registeringUsers"),
                    "@odata.type");
                if (!string.Equals(registeringType, NoMembershipType, System.StringComparison.OrdinalIgnoreCase))
                {
                    issues.Add($"Registering users are granted local administrator rights ({registeringType}). Configure deviceRegistrationPolicy to deny.");
                }
            }
            else
            {
                issues.Add("DeviceRegistrationPolicy cache not found — cannot verify whether registering users get local admin rights.");
            }

            // 2. LAPS policy deployed and assigned.
            if (Any(configPolicies))
            {
                var laps = new List<JsonElement>();
                foreach (var p in Items(configPolicies))
                {
                    if (!Like(Str(p, "platforms"), "*windows10*")) continue;
                    var tr = Prop(p, "templateReference");
                    if (!(tr.ValueKind == JsonValueKind.Object && StrEq(tr, "templateFamily", "endpointSecurityAccountProtection"))) continue;
                    var defIds = Chain(p, "settings", "settingInstance", "settingDefinitionId");
                    if (defIds.Any(x => ValEq(x, LapsDefId))) laps.Add(p);
                }
                int assignedLaps = laps.Count(HasAssignments);
                if (assignedLaps == 0)
                {
                    issues.Add("No assigned Windows LAPS policy found in Intune. Without LAPS, the local administrator credential is shared/static, contradicting SMB1001 2.2.");
                }
            }
            else
            {
                issues.Add("IntuneConfigurationPolicies cache not found — cannot verify Windows LAPS deployment.");
            }

            if (issues.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Registering users are not granted local administrator rights, and an assigned Windows LAPS policy manages the local admin credential.");
            }

            var sb = new StringBuilder();
            sb.Append("SMB1001 (2.2) requires employees to lack administrative privileges on their devices.\n\n");
            sb.Append(string.Join("\n", issues.Select(i => $"- {i}")));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
