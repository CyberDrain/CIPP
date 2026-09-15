using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guest access is limited to approved tenants.
    /// Port of Invoke-CippTestZTNA21822. Parses the B2BManagementPolicy 'definition' JSON and passes
    /// when InvitationsAllowedAndBlockedDomainsPolicy.AllowedDomains is non-empty.
    /// </summary>
    public sealed class ZTNA21822 : ICippTest
    {
        public string Id => "ZTNA21822";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var b2b = data.Get("B2BManagementPolicy");

            var allowed = new List<string>();
            var blocked = new List<string>();

            foreach (var rec in Items(b2b))
            {
                var def = Prop(rec, "definition");
                foreach (var jsonStr in DefinitionStrings(def))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(jsonStr);
                        if (!TryProp(doc.RootElement, "B2BManagementPolicy", out var policy)) continue;
                        if (!TryProp(policy, "InvitationsAllowedAndBlockedDomainsPolicy", out var invPolicy)) continue;
                        foreach (var d in Arr(invPolicy, "AllowedDomains")) { var s = AsString(d); if (s != null) allowed.Add(s); }
                        foreach (var d in Arr(invPolicy, "BlockedDomains")) { var s = AsString(d); if (s != null) blocked.Add(s); }
                    }
                    catch (JsonException) { /* malformed definition — ignore, matches PS best-effort */ }
                }
            }

            bool passed = allowed.Count > 0;

            var sb = new StringBuilder(passed
                ? "Guest access is limited to approved tenants.\n"
                : "Guest access is not limited to approved tenants.\n");

            sb.Append("\n\n## [Collaboration restrictions](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/~/Settings/menuId/)\n\n");
            sb.Append("The tenant is configured to: ");
            if (passed)
                sb.Append("**Allow invitations only to the specified domains (most restrictive)** ✅\n");
            else if (blocked.Count > 0)
                sb.Append("**Deny invitations to the specified domains** ❌\n");
            else
                sb.Append("**Allow invitations to be sent to any domain (most inclusive)** ❌\n");

            if (allowed.Count > 0 || blocked.Count > 0)
            {
                sb.Append("| Domain | Status |\n");
                sb.Append("| :--- | :--- |\n");
                foreach (var d in allowed) sb.Append($"| {d} | ✅ Allowed |\n");
                foreach (var d in blocked) sb.Append($"| {d} | ❌ Blocked |\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        private static IEnumerable<string> DefinitionStrings(JsonElement def)
        {
            if (def.ValueKind == JsonValueKind.String)
            {
                var s = def.GetString();
                if (!string.IsNullOrEmpty(s)) yield return s!;
            }
            else if (def.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in def.EnumerateArray())
                    if (el.ValueKind == JsonValueKind.String)
                    {
                        var s = el.GetString();
                        if (!string.IsNullOrEmpty(s)) yield return s!;
                    }
            }
        }
    }
}
