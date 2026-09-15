using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (4.2) — Device enrollment for personally owned devices SHALL be blocked by default.
    /// Port of Invoke-CippTestCIS_4_2. Single source: IntuneDeviceEnrollmentConfigurations.
    /// </summary>
    public sealed class CIS_4_2 : ICippTest
    {
        public string Id => "CIS_4_2";

        private static readonly string[] Platforms =
        {
            "androidForWorkRestriction", "androidRestriction", "iosRestriction",
            "macOSRestriction", "windowsRestriction"
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var enrollment = data.Get("IntuneDeviceEnrollmentConfigurations");
            if (!Any(enrollment))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "IntuneDeviceEnrollmentConfigurations cache not found. Please refresh the cache for this tenant.");
            }

            // PS: ($odataType -eq platformRestrictions AND priority -eq 0) OR displayName -eq 'All Users', first match.
            JsonElement? defaultPlatform = null;
            foreach (var e in enrollment.EnumerateArray())
            {
                bool a = StrEq(e, "@odata.type", "#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration")
                         && PriorityIsZero(e);
                bool c = StrEq(e, "displayName", "All Users");
                if (a || c) { defaultPlatform = e; break; }
            }

            // Fallback: first record that HAS an 'androidRestriction' property.
            if (defaultPlatform == null)
            {
                foreach (var e in enrollment.EnumerateArray())
                {
                    if (TryProp(e, "androidRestriction", out _)) { defaultPlatform = e; break; }
                }
            }

            if (defaultPlatform == null)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Default Device Platform Restriction policy not found in cache.");
            }

            var dp = defaultPlatform.Value;
            var failures = new List<string>();
            foreach (var p in Platforms)
            {
                if (!TryProp(dp, p, out var r) || !PsTruthy(r)) continue;
                if (!IsTrue(r, "personalDeviceEnrollmentBlocked") && !IsTrue(r, "platformBlocked"))
                {
                    failures.Add($"{p} : personal enrollment NOT blocked");
                }
            }

            if (failures.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "All platforms block personally-owned device enrollment in the default policy.");
            }

            var sb = new StringBuilder();
            sb.Append("Personal enrollment is allowed for one or more platforms in the default Device Platform Restriction policy:\n\n");
            var bullets = new List<string>();
            foreach (var f in failures) bullets.Add($"- {f}");
            sb.Append(string.Join("\n", bullets));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }

        // PS: $_.priority -eq 0 — a missing property does not equal 0.
        private static bool PriorityIsZero(JsonElement e)
        {
            if (!TryProp(e, "priority", out var v)) return false;
            if (v.ValueKind == JsonValueKind.Number) return v.TryGetDouble(out var d) && d == 0;
            if (v.ValueKind == JsonValueKind.String) return v.GetString() == "0";
            return false;
        }
    }
}
