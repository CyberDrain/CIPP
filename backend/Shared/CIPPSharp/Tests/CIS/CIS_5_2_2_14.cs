using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.14) — Named locations are defined and applied.
    /// Port of Invoke-CippTestCIS_5_2_2_14. Any enabled CA policy that references a named location
    /// GUID (an include/exclude location that is neither 'All' nor 'AllTrusted').
    /// </summary>
    public sealed class CIS_5_2_2_14 : ICippTest
    {
        public string Id => "CIS_5_2_2_14";

        private static bool NamedLocationRef(string s) => s.Length > 0 && !InListCI(s, "All", "AllTrusted");

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && PathTruthy(p, "conditions", "locations")
                    && (AnyString(Path(p, "conditions", "locations", "includeLocations"), NamedLocationRef)
                        || AnyString(Path(p, "conditions", "locations", "excludeLocations"), NamedLocationRef)))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} enabled Conditional Access policy/policies reference a named location:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy references a defined named location in its location conditions.");
        }
    }
}
