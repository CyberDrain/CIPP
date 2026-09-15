using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All guests have a sponsor.
    /// Port of Invoke-CippTestZTNA21877. Skipped on no Guests data; Passed when every guest has at
    /// least one sponsor.
    /// </summary>
    public sealed class ZTNA21877 : ICippTest
    {
        public string Id => "ZTNA21877";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var guests = data.Get("Guests");
            if (!Any(guests))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int total = guests.GetArrayLength();

            var without = new List<JsonElement>();
            foreach (var g in Items(guests))
                if (ArrayLen(g, "sponsors") == 0) without.Add(g);

            if (without.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "All guest accounts in the tenant have an assigned sponsor");

            var lines = new List<string>
            {
                $"Found {without.Count} guest user(s) without sponsors out of {total} total guests.",
                "",
                $"**Total guests:** {total}",
                $"**Guests without sponsors:** {without.Count}",
                $"**Guests with sponsors:** {total - without.Count}",
                "",
                "**Top 10 guests without sponsors:**"
            };

            for (int i = 0; i < without.Count && i < 10; i++)
                lines.Add($"- {Text(without[i], "displayName")} ({Text(without[i], "userPrincipalName")})");

            if (without.Count > 10)
                lines.Add($"- ... and {without.Count - 10} more guest(s)");

            lines.Add("");
            lines.Add("**Recommendation:** Assign sponsors to all guest accounts for better accountability and lifecycle management.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
