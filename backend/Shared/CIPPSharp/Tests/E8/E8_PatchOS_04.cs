using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Patch Operating Systems) — Windows Update Ring quality update deferral is 14 days or
    /// less. Port of Invoke-CippTestE8_PatchOS_04. Reads IntuneDeviceConfigurations
    /// (windowsUpdateForBusinessConfiguration).
    /// </summary>
    public sealed class E8_PatchOS_04 : ICippTest
    {
        public string Id => "E8_PatchOS_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var rings = CippTestHelpers.Items(data.Get("IntuneDeviceConfigurations"))
                .Where(p => CippTestHelpers.StrEq(p, "@odata.type", "#microsoft.graph.windowsUpdateForBusinessConfiguration"))
                .ToList();

            if (rings.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No `windowsUpdateForBusinessConfiguration` Update Ring policies cached for this tenant; quality deferral cannot be evaluated automatically.");
            }

            var bad = new List<(string Ring, string Deferral)>();
            foreach (var r in rings)
            {
                if (!CippTestHelpers.TryProp(r, "qualityUpdatesDeferralPeriodInDays", out var d)) continue;
                if (d.ValueKind != JsonValueKind.Number) continue;
                if (d.GetDouble() > 14)
                {
                    bad.Add((CippTestHelpers.Str(r, "displayName") ?? "", d.GetRawText()));
                }
            }

            if (bad.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {rings.Count} Update Ring policy/policies defer quality updates by 14 days or less.");
            }

            var sb = new StringBuilder();
            sb.Append($"{bad.Count} Update Ring policy/policies defer quality updates by more than 14 days:\n\n");
            var rows = bad.Select(b => (IReadOnlyList<string>)new[] { b.Ring, b.Deferral });
            sb.Append(Markdown.Table(new[] { "Ring", "Deferral (days)" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
