using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.16) — Token Protection is enforced for session tokens.
    /// Port of Invoke-CippTestCIS_5_2_2_16. Any enabled CA policy enforcing a secure sign-in session
    /// for Exchange Online, SharePoint Online and Teams on Windows desktop/mobile clients.
    /// </summary>
    public sealed class CIS_5_2_2_16 : ICippTest
    {
        public string Id => "CIS_5_2_2_16";

        private const string ExchangeOnline = "00000002-0000-0ff1-ce00-000000000000";
        private const string SharePointOnline = "00000003-0000-0ff1-ce00-000000000000";
        private const string TeamsServices = "cc15fd57-2c6c-4117-a88c-83b1d56b4bbe";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                var apps = Path(p, "conditions", "applications", "includeApplications");
                if (StrEq(p, "state", "enabled")
                    && ArrNotContainsCI(Path(p, "conditions", "users", "includeUsers"), "None")
                    && ArrContainsCI(apps, ExchangeOnline)
                    && ArrContainsCI(apps, SharePointOnline)
                    && ArrContainsCI(apps, TeamsServices)
                    && ArrContainsCI(Path(p, "conditions", "platforms", "includePlatforms"), "windows")
                    && ArrContainsCI(Path(p, "conditions", "clientAppTypes"), "mobileAppsAndDesktopClients")
                    && PathTruthy(p, "sessionControls", "secureSignInSession")
                    && LeafIsTrue(Path(p, "sessionControls", "secureSignInSession", "isEnabled")))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies enforce Token Protection for sign-in sessions:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy enforces Token Protection (secure sign-in session) for Exchange Online, SharePoint Online and Teams on Windows desktop/mobile clients.");
        }
    }
}
