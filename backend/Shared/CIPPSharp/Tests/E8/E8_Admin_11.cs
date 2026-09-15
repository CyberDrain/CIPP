using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (Restrict Admin Privileges) — PIM role eligibility expires within 12 months (no
    /// permanent eligibility) (ISM-1647). Port of Invoke-CippTestE8_Admin_11. Reads
    /// RoleEligibilitySchedules.
    /// </summary>
    public sealed class E8_Admin_11 : ICippTest
    {
        public string Id => "E8_Admin_11";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var schedules = data.Get("RoleEligibilitySchedules");
            if (!CippTestHelpers.Any(schedules))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "RoleEligibilitySchedules cache not found (no PIM in use, or P2 not licensed).");
            }

            var maxFuture = DateTime.UtcNow.AddDays(366);
            int total = 0;
            var bad = new List<(string Principal, string RoleId, string Reason)>();
            foreach (var s in CippTestHelpers.Items(schedules))
            {
                total++;
                var type = CippTestHelpers.PathStr(s, "scheduleInfo", "expiration", "type");
                var end = CippTestHelpers.PathStr(s, "scheduleInfo", "expiration", "endDateTime");
                if (string.Equals(type, "noExpiration", StringComparison.OrdinalIgnoreCase) || string.IsNullOrEmpty(end))
                {
                    bad.Add((CippTestHelpers.Str(s, "principalId") ?? "", CippTestHelpers.Str(s, "roleDefinitionId") ?? "", "No expiration"));
                }
                else if (CippTestHelpers.TryParseUtc(end, out var endDt) && endDt > maxFuture)
                {
                    bad.Add((CippTestHelpers.Str(s, "principalId") ?? "", CippTestHelpers.Str(s, "roleDefinitionId") ?? "", $"Expires {end} (>12 months)"));
                }
            }

            if (bad.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {total} PIM eligibility schedule(s) expire within 12 months.");
            }

            var sb = new StringBuilder();
            sb.Append($"{bad.Count} of {total} PIM eligibility schedule(s) do not expire within 12 months:\n\n");
            var rows = bad.Take(50).Select(b => (IReadOnlyList<string>)new[] { b.Principal, b.RoleId, b.Reason });
            sb.Append(Markdown.Table(new[] { "Principal", "Role", "Reason" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
