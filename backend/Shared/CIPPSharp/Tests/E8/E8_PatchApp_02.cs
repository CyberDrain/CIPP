using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Patch Applications) — managed devices have synced with Intune within the last 14
    /// days. Port of Invoke-CippTestE8_PatchApp_02. Reads ManagedDevices; a device is stale when it
    /// has never synced or its lastSyncDateTime is older than 14 days.
    /// </summary>
    public sealed class E8_PatchApp_02 : ICippTest
    {
        public string Id => "E8_PatchApp_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var devices = data.Get("ManagedDevices");
            if (!CippTestHelpers.Any(devices))
            {
                return new CippTestResult(TestStatus.Skipped, "No ManagedDevices cached for this tenant.");
            }

            // Threshold in UTC; PS compares local-parsed vs local-now, the offset cancels so the
            // verdict is identical. (Display date may differ by up to a day near midnight — cosmetic.)
            var threshold = DateTime.UtcNow.AddDays(-14);
            var stale = new List<(string Device, string LastSync)>();
            int total = 0;

            foreach (var d in CippTestHelpers.Items(devices))
            {
                total++;
                var device = CippTestHelpers.Str(d, "deviceName") ?? "";
                var lastSync = CippTestHelpers.Str(d, "lastSyncDateTime");
                if (string.IsNullOrEmpty(lastSync))
                {
                    stale.Add((device, "never"));
                    continue;
                }
                if (CippTestHelpers.TryParseDate(lastSync, out var dt) && dt < threshold)
                {
                    stale.Add((device, dt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)));
                }
            }

            if (stale.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {total} managed device(s) have synced with Intune within the last 14 days.");
            }

            var rows = stale.Take(50)
                .Select(s => (IReadOnlyList<string>)new[] { s.Device, s.LastSync });
            var sb = new StringBuilder();
            sb.Append($"{stale.Count} of {total} managed device(s) have not synced for >14 days; their patch state is unknown:\n\n");
            sb.Append(Markdown.Table(new[] { "Device", "Last sync" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
