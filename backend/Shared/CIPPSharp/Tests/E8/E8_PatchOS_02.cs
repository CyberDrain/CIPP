using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Patch Operating Systems) — all managed Windows devices run a supported build
    /// (Win10 22H2 / Win11 22H2+). Port of Invoke-CippTestE8_PatchOS_02. Reads ManagedDevices and
    /// checks the build number (3rd dotted segment of osVersion).
    /// </summary>
    public sealed class E8_PatchOS_02 : ICippTest
    {
        public string Id => "E8_PatchOS_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var devices = data.Get("ManagedDevices");
            if (!CippTestHelpers.Any(devices))
            {
                return new CippTestResult(TestStatus.Skipped, "No ManagedDevices cached for this tenant.");
            }

            var windows = CippTestHelpers.Items(devices)
                .Where(d => string.Equals(CippTestHelpers.Str(d, "operatingSystem"), "Windows",
                    System.StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (windows.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped, "No Windows managed devices found.");
            }

            // Win10 22H2 = 19045.x ; Win11 22H2 = 22621.x ; Win11 23H2 = 22631.x ; Win11 24H2 = 26100.x
            var unsupported = new List<(string Device, string OsVersion, string Reason)>();
            foreach (var d in windows)
            {
                var v = CippTestHelpers.Str(d, "osVersion");
                if (string.IsNullOrEmpty(v)) continue;
                var parts = v.Split('.');
                if (parts.Length < 3) continue;
                if (!int.TryParse(parts[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out var build)) continue;

                string? reason = null;
                if (build < 19045) reason = "Windows 10 build < 22H2 (out of support)";
                else if (build >= 20000 && build < 22621) reason = "Windows 11 build < 22H2 (out of support)";

                if (reason != null)
                {
                    unsupported.Add((CippTestHelpers.Str(d, "deviceName") ?? "", v, reason));
                }
            }

            if (unsupported.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {windows.Count} Windows device(s) run a supported build.");
            }

            var rows = unsupported.Take(50)
                .Select(u => (IReadOnlyList<string>)new[] { u.Device, u.OsVersion, u.Reason });
            var sb = new StringBuilder();
            sb.Append($"{unsupported.Count} of {windows.Count} Windows device(s) are on unsupported builds:\n\n");
            sb.Append(Markdown.Table(new[] { "Device", "OS version", "Reason" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
