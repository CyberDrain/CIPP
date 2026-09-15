using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (MFA) — all member users are registered/capable for MFA. Port of
    /// Invoke-CippTestE8_MFA_01. Joins UserRegistrationDetails + Users on lowercased UPN; an enabled
    /// non-guest user with no isMfaCapable registration record is non-compliant.
    /// </summary>
    public sealed class E8_MFA_01 : ICippTest
    {
        public string Id => "E8_MFA_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var reg = data.Get("UserRegistrationDetails");
            var users = data.Get("Users");
            if (!CippTestHelpers.Any(reg) || !CippTestHelpers.Any(users))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (UserRegistrationDetails or Users) not found. Please refresh the cache for this tenant.");
            }

            var regByUpn = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var r in CippTestHelpers.Items(reg))
            {
                var upn = CippTestHelpers.Str(r, "userPrincipalName");
                if (!string.IsNullOrEmpty(upn)) regByUpn[upn!.ToLowerInvariant()] = r;
            }

            var memberUsers = CippTestHelpers.Items(users)
                .Where(u => CippTestHelpers.IsTrue(u, "accountEnabled") && !CippTestHelpers.StrEq(u, "userType", "Guest"))
                .ToList();

            var notCapable = new List<JsonElement>();
            foreach (var u in memberUsers)
            {
                var upn = CippTestHelpers.Str(u, "userPrincipalName") ?? "";
                if (!regByUpn.TryGetValue(upn.ToLowerInvariant(), out var r) || !CippTestHelpers.IsTrue(r, "isMfaCapable"))
                    notCapable.Add(u);
            }

            if (notCapable.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {memberUsers.Count} enabled member users are MFA capable.");
            }

            var sb = new StringBuilder();
            sb.Append($"{notCapable.Count} of {memberUsers.Count} enabled member users are not MFA capable:\n\n");
            var rows = notCapable.Take(50).Select(u => (IReadOnlyList<string>)new[]
            {
                CippTestHelpers.Str(u, "userPrincipalName") ?? "", CippTestHelpers.Str(u, "displayName") ?? ""
            });
            sb.Append(Markdown.Table(new[] { "UPN", "Display Name" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
