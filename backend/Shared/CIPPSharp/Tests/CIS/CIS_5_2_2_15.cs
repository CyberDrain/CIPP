using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.15) — Exclusionary geographic access controls are utilized.
    /// Port of Invoke-CippTestCIS_5_2_2_15. Any enabled block policy for All users/apps that includes
    /// an untrusted/selected location and excludes trusted locations.
    /// </summary>
    public sealed class CIS_5_2_2_15 : ICippTest
    {
        public string Id => "CIS_5_2_2_15";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && ArrContainsCI(Path(p, "conditions", "users", "includeUsers"), "All")
                    && ArrContainsCI(Path(p, "conditions", "applications", "includeApplications"), "All")
                    && ArrContainsCI(Path(p, "grantControls", "builtInControls"), "block")
                    && PathTruthy(p, "conditions", "locations")
                    // Include at least one untrusted/selected location (not just 'AllTrusted').
                    && AnyString(Path(p, "conditions", "locations", "includeLocations"), s => s.Length > 0 && !InListCI(s, "AllTrusted"))
                    // Exclude trusted locations: AllTrusted, or at least one location GUID.
                    && (ArrContainsCI(Path(p, "conditions", "locations", "excludeLocations"), "AllTrusted")
                        || AnyString(Path(p, "conditions", "locations", "excludeLocations"), s => s.Length > 0)))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} enabled Conditional Access policy/policies block access from untrusted locations while excluding trusted locations:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled block policy was found that includes untrusted locations for all users/apps and excludes trusted locations.");
        }
    }
}
