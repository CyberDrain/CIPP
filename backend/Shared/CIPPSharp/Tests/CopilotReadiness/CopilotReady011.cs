using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant has at least one enabled Conditional Access policy (security prerequisite for Copilot).
    /// Port of Invoke-CippTestCopilotReady011. Single source: ConditionalAccessPolicies.
    /// </summary>
    public sealed class CopilotReady011 : ICippTest
    {
        public string Id => "CopilotReady011";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Conditional Access policy data found in database. The tenant may not have Azure AD Premium, or data collection may not yet have run.");
            }

            var enabled = new List<JsonElement>();
            int reportOnly = 0;
            foreach (var p in caPolicies.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")) enabled.Add(p);
                else if (StrEq(p, "state", "enabledForReportingButNotEnforced")) reportOnly++;
            }

            if (enabled.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"**{enabled.Count} enabled Conditional Access polic{(enabled.Count == 1 ? "y" : "ies")}** found in the tenant.\n\n");
                var rows = enabled
                    .OrderBy(p => Str(p, "displayName") ?? "", StringComparer.OrdinalIgnoreCase)
                    .Select(p => (IReadOnlyList<string>)new[] { Cell(Prop(p, "displayName")), "Enabled" })
                    .ToList();
                sb.Append(Markdown.Table(new[] { "Policy Name", "State" }, rows));
                if (reportOnly > 0)
                {
                    sb.Append($"\n*{reportOnly} additional polic{(reportOnly == 1 ? "y is" : "ies are")} in report-only mode and not enforcing access controls.*");
                }
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("No enabled Conditional Access policies were found in this tenant.\n\n");
            if (reportOnly > 0)
            {
                f.Append($"**{reportOnly} polic{(reportOnly == 1 ? "y is" : "ies are")} in report-only mode** but not enforcing.\n\n");
            }
            f.Append("Conditional Access is the primary mechanism for enforcing MFA, device compliance, and access controls in Entra ID. ");
            f.Append("Before deploying Copilot, establish at least a baseline CA policy requiring MFA for all users. ");
            f.Append("See [Microsoft CA policy templates](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common) to get started.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
