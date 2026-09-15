using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Users cannot freely create groups, tenants, or register applications (governance baseline).
    /// Port of Invoke-CippTestCopilotReady012. Single source: AuthorizationPolicy (singleton record).
    /// </summary>
    public sealed class CopilotReady012 : ICippTest
    {
        // Ordered to match the PS [ordered] hashtable: key -> friendly label.
        private static readonly (string Key, string Label)[] Checks =
        {
            ("allowedToCreateGroups", "Create Microsoft 365 groups"),
            ("allowedToCreateTenants", "Create new Azure AD tenants"),
            ("allowedToCreateApps", "Register applications"),
            ("allowedToCreateSecurityGroups", "Create security groups"),
        };

        public string Id => "CopilotReady012";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authPolicy = data.Get("AuthorizationPolicy");
            if (!Any(authPolicy))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No authorization policy data found in database. Data collection may not yet have run for this tenant.");
            }

            JsonElement cfg = default;
            foreach (var el in authPolicy.EnumerateArray()) { cfg = el; break; }
            var perms = Prop(cfg, "defaultUserRolePermissions");

            var issues = new List<string>();
            var restricted = new List<string>();
            foreach (var (key, label) in Checks)
            {
                if (IsTrue(perms, key)) issues.Add(label);
                else restricted.Add(label);
            }

            // Also check allowedToCreateTenants at the top-level policy (older API surface).
            if (IsTrue(cfg, "allowedToCreateTenants") && !issues.Contains("Create new Azure AD tenants"))
                issues.Add("Create new Azure AD tenants (top-level policy)");

            if (issues.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All user self-service creation permissions are restricted — users cannot create groups, tenants, or register applications without admin involvement.\n\n");
                sb.Append("This reduces shadow IT risk and ensures governance controls apply to new M365 resources before Copilot can interact with them.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"**{issues.Count} user permission{(issues.Count == 1 ? "" : "s")}** allow unrestricted self-service creation.\n\n");
            var rows = new List<IReadOnlyList<string>>();
            foreach (var issue in issues) rows.Add(new[] { issue, "⚠️ Unrestricted" });
            foreach (var ok in restricted) rows.Add(new[] { ok, "✅ Restricted" });
            f.Append(Markdown.Table(new[] { "Permission", "Status" }, rows));
            f.Append("\nWith Copilot deployed, unrestricted group and app creation increases the risk of uncontrolled data exposure. ");
            f.Append("Restrict these permissions via **Entra ID → User settings** and **Group settings** to ensure new resources go through a governed process.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
