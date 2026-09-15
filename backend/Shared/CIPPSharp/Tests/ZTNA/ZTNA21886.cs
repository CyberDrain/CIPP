using System;
using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Applications are configured for automatic user provisioning.
    /// Port of Invoke-CippTestZTNA21886. Skipped on no ServicePrincipals data; Passed when no SSO apps
    /// exist. Otherwise returns the non-standard status 'Investigate' verbatim with a per-SSO-mode
    /// breakdown (provisioning state cannot be validated from cache).
    /// </summary>
    public sealed class ZTNA21886 : ICippTest
    {
        public string Id => "ZTNA21886";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var sps = data.Get("ServicePrincipals");
            if (!Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var withSso = new List<JsonElement>();
            foreach (var sp in Items(sps))
                if (PropIn(sp, "preferredSingleSignOnMode", "password", "saml", "oidc") && IsTrue(sp, "accountEnabled"))
                    withSso.Add(sp);

            if (withSso.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No applications configured for SSO found");

            // Group by SSO mode preserving first-occurrence order (Group-Object semantics).
            var order = new List<string>();
            var groups = new Dictionary<string, List<JsonElement>>(StringComparer.OrdinalIgnoreCase);
            foreach (var sp in withSso)
            {
                var mode = Str(sp, "preferredSingleSignOnMode") ?? "";
                if (!groups.TryGetValue(mode, out var list))
                {
                    list = new List<JsonElement>();
                    groups[mode] = list;
                    order.Add(mode);
                }
                list.Add(sp);
            }

            var lines = new List<string>
            {
                $"Found {withSso.Count} application(s) configured for SSO.",
                "",
                "**Applications with SSO enabled:**"
            };

            foreach (var mode in order)
            {
                var list = groups[mode];
                lines.Add("");
                lines.Add($"**{mode.ToUpperInvariant()} SSO** ({list.Count} app(s)):");
                for (int i = 0; i < list.Count && i < 5; i++)
                    lines.Add($"- {Text(list[i], "displayName")}");
                if (list.Count > 5)
                    lines.Add($"- ... and {list.Count - 5} more");
            }

            lines.Add("");
            lines.Add("**Note:** Provisioning template and job validation requires Graph API synchronization endpoint not available in cache.");
            lines.Add("");
            lines.Add("**Recommendation:** Configure automatic user provisioning for applications that support it to ensure consistent access management.");

            return new CippTestResult("Investigate", string.Join("\n", lines));
        }
    }
}
