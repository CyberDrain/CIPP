using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.1) — MFA SHALL be enabled for all users in administrative roles. Port of
    /// Invoke-CippTestCIS_5_2_2_1. Sources: ConditionalAccessPolicies + privileged roles
    /// (Get-CippDbRole -IncludePrivilegedRoles). CA includeRoles reference role TEMPLATE ids.
    /// </summary>
    public sealed class CIS_5_2_2_1 : ICippTest
    {
        public string Id => "CIS_5_2_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            var privRoles = GetPrivilegedRoles(data);

            if (!Any(ca) || privRoles.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (ConditionalAccessPolicies or Roles) not found. Please refresh the cache for this tenant.");
            }

            // Privileged role TEMPLATE ids present in the tenant (PS HashSet[string], ordinal).
            var privRoleIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var r in privRoles)
            {
                var tid = Str(r, "roleTemplateId");
                if (!string.IsNullOrEmpty(tid)) privRoleIds.Add(tid!);
            }

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (!StrEq(p, "state", "enabled")) continue;

                var grant = PropPath(p, "grantControls");
                if (!PsTruthy(grant)) continue;

                bool mfa = ContainsCI(PropPath(grant, "builtInControls"), "mfa");
                bool authStrength = PsTruthy(PropPath(grant, "authenticationStrength"));
                if (!(mfa || authStrength)) continue;

                var includeRoles = PropPath(p, "conditions.users.includeRoles");
                if (!PsTruthy(includeRoles)) continue;

                bool anyPriv = false;
                foreach (var ir in Items(includeRoles))
                {
                    if (ir.ValueKind == JsonValueKind.String && privRoleIds.Contains(ir.GetString()!)) { anyPriv = true; break; }
                }
                if (anyPriv) matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies enforce MFA on privileged roles:\n\n");
                var bullets = new List<string>();
                foreach (var p in matching) bullets.Add($"- {Str(p, "displayName")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets privileged roles with MFA. Create a policy with includeRoles = (privileged role IDs) and grant control = MFA.");
        }
    }
}
