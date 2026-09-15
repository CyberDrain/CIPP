using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Conditional Access policies for Privileged Access Workstations are configured.
    /// Port of Invoke-CippTestZTNA21830. Among enabled CA policies targeting privileged roles (by
    /// role id), requires at least one with a compliant-device control AND one with an exclude device
    /// filter that blocks access.
    /// </summary>
    public sealed class ZTNA21830 : ICippTest
    {
        public string Id => "ZTNA21830";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            if (privilegedRoles.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var privilegedRoleIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var role in privilegedRoles) { var id = Str(role, "id"); if (id != null) privilegedRoleIds.Add(id); }

            var compliantDevice = new List<JsonElement>();
            var deviceFilter = new List<JsonElement>();

            foreach (var p in Items(data.Get("ConditionalAccessPolicies")))
            {
                if (!StrEq(p, "state", "enabled")) continue;

                bool targets = false;
                foreach (var roleId in FlattenStrings(p, "conditions", "users", "includeRoles"))
                    if (privilegedRoleIds.Contains(roleId)) { targets = true; break; }
                if (!targets) continue;

                if (FlattenContains(p, "compliantDevice", "grantControls", "builtInControls"))
                    compliantDevice.Add(p);

                var df = Nested(p, "conditions", "devices", "deviceFilter");
                bool hasExclude = df.ValueKind != JsonValueKind.Undefined && df.ValueKind != JsonValueKind.Null && StrEq(df, "mode", "exclude");

                var controls = Nested(p, "grantControls", "builtInControls");
                bool noControls = controls.ValueKind == JsonValueKind.Undefined || controls.ValueKind == JsonValueKind.Null
                    || (controls.ValueKind == JsonValueKind.Array && controls.GetArrayLength() == 0);
                bool blocks = noControls || FlattenContains(p, "block", "grantControls", "builtInControls");

                if (hasExclude && blocks) deviceFilter.Add(p);
            }

            bool passed = compliantDevice.Count > 0 && deviceFilter.Count > 0;

            var sb = new StringBuilder(passed
                ? "Conditional Access policies restrict privileged role access to PAW devices."
                : "No Conditional Access policies found that restrict privileged roles to PAW device.");

            string cdMark = compliantDevice.Count > 0 ? "✅" : "❌";
            string dfMark = deviceFilter.Count > 0 ? "✅" : "❌";

            sb.Append($"\n\n**{cdMark} Found {compliantDevice.Count} policy(s) with compliant device control targeting all privileged roles**\n");
            foreach (var p in compliantDevice)
                sb.Append($"- **Policy:** [{Text(p, "displayName")}](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/{Str(p, "id")})\n");

            sb.Append($"\n\n**{dfMark} Found {deviceFilter.Count} policy(s) with PAW/SAW device filter targeting all privileged roles**\n");
            foreach (var p in deviceFilter)
                sb.Append($"- **Policy:** [{Text(p, "displayName")}](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/{Str(p, "id")})\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
