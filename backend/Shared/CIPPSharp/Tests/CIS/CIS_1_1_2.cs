using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.1.2) — At least two emergency access (break-glass) accounts SHALL be defined.
    /// Port of Invoke-CippTestCIS_1_1_2. Flags cloud-only Global Administrators whose UPN matches
    /// common break-glass keywords.
    /// </summary>
    public sealed class CIS_1_1_2 : ICippTest
    {
        private const string BreakGlassPattern = "breakglass|break-glass|emergency|cipp-bg|bg-admin";

        public string Id => "CIS_1_1_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("Roles") || !data.Has("Users"))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Roles or Users) not found. Please refresh the cache for this tenant.");
            }

            var ga = GlobalAdminRole(data);
            if (ga == null)
            {
                return new CippTestResult(TestStatus.Failed,
                    "Global Administrator role not found in tenant role definitions.");
            }

            var gaIds = CollectGaUserIds(data, ga.Value);
            var gaUsers = UsersByIds(data, gaIds);

            var likelyBg = new List<JsonElement>();
            foreach (var u in gaUsers)
            {
                var upn = Str(u, "userPrincipalName");
                if (MatchCI(upn, BreakGlassPattern) && !IsTrue(u, "onPremisesSyncEnabled"))
                    likelyBg.Add(u);
            }

            if (likelyBg.Count >= 2)
            {
                var sb = new StringBuilder();
                sb.Append($"Found {likelyBg.Count} likely emergency access accounts. Verify they meet break-glass requirements (excluded from CA, monitored, MFA-registered).\n\n");
                var lines = new List<string>();
                foreach (var u in likelyBg) lines.Add($"- {Str(u, "userPrincipalName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                $"Found {likelyBg.Count} cloud-only Global Administrator(s) matching break-glass naming. Required: at least 2.\n\nNote: This test only flags GA accounts whose UPN matches common break-glass keywords. If your break-glass accounts use a different naming convention this test will report a false negative.");
        }
    }
}
