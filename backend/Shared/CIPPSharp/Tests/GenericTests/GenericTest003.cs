using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// License Renewal Report — upcoming renewal dates, terms, and trial status.
    /// Port of Invoke-CippTestGenericTest003. Single source: LicenseOverview (TermInfo per SKU).
    /// Always Informational (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest003 : ICippTest
    {
        private sealed class Renewal
        {
            public string License = "";
            public string Status = "";
            public string Term = "";
            public string Seats = "";
            public double? Days;      // null when the field is $null/absent
            public string DaysCell = "";
            public string NextRenewal = "Unknown";
            public bool IsTrial;
        }

        public string Id => "GenericTest003";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var licenseData = data.Get("LicenseOverview");
            if (!Any(licenseData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No license data found in the reporting database. Please sync the License Overview cache first.");
            }

            bool hasRenewals = false;
            int trialCount = 0;
            var renewals = new List<Renewal>();

            foreach (var license in licenseData.EnumerateArray())
            {
                var licenseName = Str(license, "License") ?? "";
                foreach (var term in RecordsOf(license, "TermInfo"))
                {
                    hasRenewals = true;
                    bool isTrial = IsTrue(term, "IsTrial");
                    if (isTrial) trialCount++;

                    string nextRenewal = "Unknown";
                    var next = Str(term, "NextLifecycle");
                    if (!string.IsNullOrEmpty(next)
                        && DateTime.TryParse(next, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt))
                        nextRenewal = dt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

                    renewals.Add(new Renewal
                    {
                        License = licenseName,
                        Status = Cell(Prop(term, "Status")),
                        Term = Cell(Prop(term, "Term")),
                        Seats = Cell(Prop(term, "TotalLicenses")),
                        Days = Num(term, "DaysUntilRenew"),
                        DaysCell = Cell(Prop(term, "DaysUntilRenew")),
                        NextRenewal = nextRenewal,
                        IsTrial = isTrial
                    });
                }
            }

            if (!hasRenewals)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No subscription renewal information is available. This may indicate non-standard licensing or the data has not been synced recently.");
            }

            var sb = new StringBuilder();
            if (trialCount > 0)
                sb.Append($"**⚠️ {trialCount} trial subscription(s) detected.** Trial licenses will expire and may cause users to lose access if not converted to paid subscriptions.\n\n");

            // PS coerces a $null DaysUntilRenew to 0 in the -le/-ge comparison, so it counts as urgent.
            int urgent = renewals.Count(r => !r.Days.HasValue || (r.Days.Value >= 0 && r.Days.Value <= 30));
            if (urgent > 0)
                sb.Append($"**🔴 {urgent} subscription(s) renewing within 30 days** — review these to ensure billing and seat counts are correct.\n\n");

            sb.Append("| License | Status | Billing Term | Seats | Renews In | Renewal Date | Trial |\n");
            sb.Append("|---------|--------|--------------|-------|-----------|--------------|-------|\n");

            // PS Sort-Object DaysUntilRenew: $null sorts first, then ascending. Stable for ties.
            foreach (var r in renewals.OrderBy(r => r.Days ?? double.NegativeInfinity))
            {
                string daysLabel = !r.Days.HasValue ? "Unknown"
                    : r.Days.Value < 0 ? "Past due"
                    : r.Days.Value == 0 ? "Today"
                    : $"{r.DaysCell} days";
                string trialLabel = r.IsTrial ? "⚠️ Yes" : "No";
                string statusIcon = r.Status.Equals("Enabled", StringComparison.OrdinalIgnoreCase) ? $"✅ {r.Status}"
                    : r.Status.Equals("Warning", StringComparison.OrdinalIgnoreCase) ? $"⚠️ {r.Status}"
                    : r.Status.Equals("Suspended", StringComparison.OrdinalIgnoreCase) ? $"🔴 {r.Status}"
                    : r.Status.Equals("Deleted", StringComparison.OrdinalIgnoreCase) ? $"❌ {r.Status}"
                    : r.Status;
                sb.Append($"| {r.License} | {statusIcon} | {r.Term} | {r.Seats} | {daysLabel} | {r.NextRenewal} | {trialLabel} |\n");
            }

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
