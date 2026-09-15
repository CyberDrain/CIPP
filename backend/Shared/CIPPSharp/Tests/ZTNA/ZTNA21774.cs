using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Microsoft services applications do not have credentials configured.
    /// Port of Invoke-CippTestZTNA21774. Service principals owned by the Microsoft first-party tenant
    /// that carry password or key credentials. Emits the PS status string "Investigate" (not one of
    /// the four standard statuses) when any are found — reproduced verbatim for parity.
    /// </summary>
    public sealed class ZTNA21774 : ICippTest
    {
        private const string MicrosoftTenantId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a";

        public string Id => "ZTNA21774";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var sps = data.Get("ServicePrincipals");
            if (!Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var microsoftSps = new List<JsonElement>();
            foreach (var s in Items(sps))
                if (StrEq(s, "appOwnerOrganizationId", MicrosoftTenantId)) microsoftSps.Add(s);

            var withPassword = new List<JsonElement>();
            var withKey = new List<JsonElement>();
            foreach (var s in microsoftSps)
            {
                if (HasCredentials(s, "passwordCredentials")) withPassword.Add(s);
                if (HasCredentials(s, "keyCredentials")) withKey.Add(s);
            }

            if (withPassword.Count + withKey.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No Microsoft services applications have credentials configured in the tenant");

            var sb = new StringBuilder();
            sb.Append($"Found Microsoft services applications with credentials configured: {withPassword.Count} with password credentials, {withKey.Count} with key credentials\n");
            sb.Append("## Service principals with password credentials:\n");
            sb.Append(JoinAppLines(withPassword));
            sb.Append("\n## Service principals with key credentials:\n");
            sb.Append(JoinAppLines(withKey));
            // PS emits the literal status 'Investigate' here (not a standard TestStatus constant).
            return new CippTestResult("Investigate", sb.ToString());
        }

        private static string JoinAppLines(List<JsonElement> items)
        {
            var lines = new List<string>(items.Count);
            foreach (var e in items) lines.Add($"- {Text(e, "displayName")} (AppId: {Text(e, "appId")})");
            return string.Join("\n", lines);
        }
    }
}
