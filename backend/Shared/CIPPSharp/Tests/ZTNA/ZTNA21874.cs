using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guest access is limited to approved tenants.
    /// Port of Invoke-CippTestZTNA21874. Skipped on no B2BManagementPolicy data. Passed when the
    /// policy definition JSON declares a non-empty allowed-domains list for B2B invitations.
    /// </summary>
    public sealed class ZTNA21874 : ICippTest
    {
        public string Id => "ZTNA21874";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var arr = data.Get("B2BManagementPolicy");
            if (!Any(arr))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement policy = default;
            foreach (var p in Items(arr)) { policy = p; break; }

            bool passed = false;

            // definition is a legacy directory-policy field: an array of JSON strings (or a single string).
            if (TryProp(policy, "definition", out var def) && def.ValueKind != JsonValueKind.Null)
            {
                string? defJson = null;
                if (def.ValueKind == JsonValueKind.Array)
                {
                    foreach (var item in def.EnumerateArray())
                    {
                        if (item.ValueKind == JsonValueKind.String) { defJson = item.GetString(); break; }
                    }
                }
                else if (def.ValueKind == JsonValueKind.String)
                {
                    defJson = def.GetString();
                }

                if (!string.IsNullOrEmpty(defJson))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(defJson!);
                        var allowed = Nested(doc.RootElement, "B2BManagementPolicy",
                            "InvitationsAllowedAndBlockedDomainsPolicy", "AllowedDomains");
                        if (allowed.ValueKind == JsonValueKind.Array && allowed.GetArrayLength() > 0)
                            passed = true;
                    }
                    catch (JsonException) { /* malformed definition → not configured */ }
                }
            }

            return passed
                ? new CippTestResult(TestStatus.Passed,
                    "✅ Allow/Deny lists of domains to restrict external collaboration are configured.")
                : new CippTestResult(TestStatus.Failed,
                    "❌ Allow/Deny lists of domains to restrict external collaboration are not configured.");
        }
    }
}
