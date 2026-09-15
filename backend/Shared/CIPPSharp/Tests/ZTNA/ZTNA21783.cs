using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Privileged Entra built-in roles are targeted with Conditional Access policies enforcing
    /// phishing-resistant methods.
    /// Port of Invoke-CippTestZTNA21783. Every privileged role's template id must appear in the
    /// includeRoles of an enabled CA policy that has an authentication strength grant control.
    /// </summary>
    public sealed class ZTNA21783 : ICippTest
    {
        public string Id => "ZTNA21783";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            var privRoles = PrivilegedRoles(data);

            if (!Any(caPolicies) || privRoles.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var coveredRoleIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in Items(caPolicies))
            {
                if (!StrEq(p, "state", "enabled")) continue;
                var authStr = Nested(p, "grantControls", "authenticationStrength");
                if (authStr.ValueKind != JsonValueKind.Object) continue;
                var includeRoles = Nested(p, "conditions", "users", "includeRoles");
                if (!Any(includeRoles)) continue;
                foreach (var id in FlattenStrings(p, "conditions", "users", "includeRoles"))
                    coveredRoleIds.Add(id);
            }

            var unprotected = new List<JsonElement>();
            foreach (var role in privRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null || !coveredRoleIds.Contains(tid)) unprotected.Add(role);
            }

            if (unprotected.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {privRoles.Count} privileged built-in roles are protected by Conditional Access policies enforcing phishing-resistant authentication");

            int protectedCount = privRoles.Count - unprotected.Count;
            var lines = new List<string>(unprotected.Count);
            foreach (var r in unprotected) lines.Add($"- {Text(r, "displayName")}");

            var sb = new StringBuilder();
            sb.Append($"Found {unprotected.Count} unprotected privileged roles out of {privRoles.Count} total ({protectedCount} protected)\n");
            sb.Append("## Unprotected privileged roles:\n");
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
