using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Enterprise applications must require explicit assignment or scoped provisioning.
    /// Port of Invoke-CippTestZTNA21869. Skipped on no ServicePrincipals data; Passed when every SSO
    /// enterprise app requires assignment. Otherwise the non-standard status 'Investigate' is returned
    /// verbatim (matching the PS test).
    /// </summary>
    public sealed class ZTNA21869 : ICippTest
    {
        public string Id => "ZTNA21869";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var sps = data.Get("ServicePrincipals");
            if (!Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var flagged = new List<JsonElement>();
            foreach (var sp in Items(sps))
            {
                if (IsFalse(sp, "appRoleAssignmentRequired")
                    && Str(sp, "preferredSingleSignOnMode") != null
                    && PropIn(sp, "preferredSingleSignOnMode", "password", "saml", "oidc")
                    && IsTrue(sp, "accountEnabled"))
                    flagged.Add(sp);
            }

            if (flagged.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "All enterprise applications have explicit assignment requirements");

            var lines = new List<string>
            {
                $"Found {flagged.Count} enterprise application(s) without assignment requirements.",
                "",
                "**Applications without user assignment requirements:**"
            };

            for (int i = 0; i < flagged.Count && i < 10; i++)
                lines.Add($"- {Text(flagged[i], "displayName")} (SSO: {Text(flagged[i], "preferredSingleSignOnMode")})");

            if (flagged.Count > 10)
                lines.Add($"- ... and {flagged.Count - 10} more application(s)");

            lines.Add("");
            lines.Add("**Note:** Full provisioning scope validation requires Graph API synchronization endpoint not available in cache.");
            lines.Add("");
            lines.Add("**Recommendation:** Enable user assignment requirements or configure scoped provisioning to limit application access.");

            return new CippTestResult("Investigate", string.Join("\n", lines));
        }
    }
}
