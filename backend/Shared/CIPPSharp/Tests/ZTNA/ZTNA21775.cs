using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant app management policy is configured.
    /// Port of Invoke-CippTestZTNA21775. DefaultAppManagementPolicy must be enabled and carry at least
    /// one active credential restriction on applications or service principals.
    /// </summary>
    public sealed class ZTNA21775 : ICippTest
    {
        private static readonly string[] Sections = { "passwordCredentials", "keyCredentials" };

        public string Id => "ZTNA21775";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("DefaultAppManagementPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            bool enabled = IsTrue(policy, "isEnabled");
            bool appHasRule = HasActiveRule(Prop(policy, "applicationRestrictions"));
            bool spHasRule = HasActiveRule(Prop(policy, "servicePrincipalRestrictions"));
            bool passed = enabled && (appHasRule || spHasRule);

            if (passed)
                return new CippTestResult(TestStatus.Passed,
                    "Tenant default app management policy is enabled with active credential restrictions.");

            var sb = new StringBuilder();
            sb.Append("Tenant default app management policy is not properly configured.\n");
            sb.Append("\n");
            sb.Append($"- **isEnabled:** {PsBool(enabled)}\n");
            sb.Append($"- **applicationRestrictions has active rule:** {PsBool(appHasRule)}\n");
            sb.Append($"- **servicePrincipalRestrictions has active rule:** {PsBool(spHasRule)}\n");
            sb.Append("\n");
            sb.Append("**Remediation:** Enable the default app management policy and configure credential restrictions to control how applications can use password and key credentials.");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        private static bool HasActiveRule(JsonElement restrictions)
        {
            if (restrictions.ValueKind != JsonValueKind.Object) return false;
            foreach (var section in Sections)
                foreach (var rule in Arr(restrictions, section))
                    if (StrEq(rule, "state", "enabled")) return true;
            return false;
        }

        private static string PsBool(bool b) => b ? "True" : "False";
    }
}
