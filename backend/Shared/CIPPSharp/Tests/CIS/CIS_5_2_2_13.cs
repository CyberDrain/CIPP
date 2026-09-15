using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.13) — Periodic reauthentication SHALL be required for all users. Port of
    /// Invoke-CippTestCIS_5_2_2_13. Single source: ConditionalAccessPolicies. Requires an enabled
    /// policy over all users/apps with a timeBased sign-in frequency of ≤ 7 days (≤ 168 hours).
    /// </summary>
    public sealed class CIS_5_2_2_13 : ICippTest
    {
        public string Id => "CIS_5_2_2_13";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
            {
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");
            }

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (!StrEq(p, "state", "enabled")) continue;
                if (!ContainsCI(PropPath(p, "conditions.users.includeUsers"), "All")) continue;
                if (!ContainsCI(PropPath(p, "conditions.applications.includeApplications"), "All")) continue;

                var sif = PropPath(p, "sessionControls.signInFrequency");
                if (!PsTruthy(sif)) continue;
                if (!IsTrue(sif, "isEnabled")) continue;
                if (!StrEq(sif, "frequencyInterval", "timeBased")) continue;

                var type = Str(sif, "type");
                long value = Int(sif, "value");
                bool ok = (string.Equals(type, "days", System.StringComparison.OrdinalIgnoreCase) && value <= 7)
                          || (string.Equals(type, "hours", System.StringComparison.OrdinalIgnoreCase) && value <= 168);
                if (ok) matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies enforce periodic reauthentication (7 days or less) for all users:\n\n");
                var bullets = new List<string>();
                foreach (var p in matching)
                {
                    var sif = PropPath(p, "sessionControls.signInFrequency");
                    bullets.Add($"- {Str(p, "displayName")} ({Cell(Prop(sif, "value"))} {Str(sif, "type")})");
                }
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets all users with a periodic (timeBased) sign-in frequency of 7 days or less.");
        }
    }
}
