using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Microsoft 365 Copilot licenses are assigned and available seats remain.
    /// Port of Invoke-CippTestCopilotReady002. Single source: LicenseOverview.
    /// </summary>
    public sealed class CopilotReady002 : ICippTest
    {
        public string Id => "CopilotReady002";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var licenseData = data.Get("LicenseOverview");
            if (licenseData.ValueKind != JsonValueKind.Array || licenseData.GetArrayLength() == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No license data found in database. Data collection may not yet have run for this tenant.");
            }

            var copilot = new List<JsonElement>();
            long totalEnabled = 0, totalConsumed = 0, totalAvailable = 0;
            foreach (var sku in licenseData.EnumerateArray())
            {
                bool isCopilot = ContainsCi(Str(sku, "License"), "Copilot");
                if (!isCopilot)
                {
                    foreach (var plan in Arr(sku, "ServicePlans"))
                    {
                        if (ContainsCi(Str(plan, "servicePlanName"), "COPILOT")) { isCopilot = true; break; }
                    }
                }
                if (isCopilot)
                {
                    copilot.Add(sku);
                    long enabled = Int(sku, "TotalLicenses");
                    long consumed = Int(sku, "CountUsed");
                    totalEnabled += enabled;
                    totalConsumed += consumed;
                    totalAvailable += (enabled - consumed);
                }
            }

            if (copilot.Count == 0)
            {
                var f = new StringBuilder();
                f.Append("No Microsoft 365 Copilot add-on licenses were found in this tenant.\n\n");
                f.Append("Purchase Microsoft 365 Copilot licenses and assign them to eligible users to enable Copilot features.");
                return new CippTestResult(TestStatus.Failed, f.ToString());
            }

            var headers = new[] { "License", "Total Seats", "Assigned", "Available" };
            var rows = new List<IReadOnlyList<string>>();
            foreach (var sku in copilot)
            {
                long available = Int(sku, "TotalLicenses") - Int(sku, "CountUsed");
                rows.Add(new[] { Cell(Prop(sku, "License")), Cell(Prop(sku, "TotalLicenses")), Cell(Prop(sku, "CountUsed")), available.ToString(System.Globalization.CultureInfo.InvariantCulture) });
            }

            if (totalConsumed == 0)
            {
                var f = new StringBuilder();
                f.Append($"Microsoft 365 Copilot licenses exist (**{totalEnabled}** seats) but **none are assigned** to any users.\n\n");
                f.Append(Markdown.Table(headers, rows));
                return new CippTestResult(TestStatus.Failed, f.ToString());
            }

            var sb = new StringBuilder();
            sb.Append("Microsoft 365 Copilot licenses are purchased and assigned.\n\n");
            sb.Append(Markdown.Table(headers, rows));
            if (totalAvailable > 0)
                sb.Append($"\n**{totalAvailable} unassigned seat(s)** are available to assign to additional users.");
            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }

        private static bool ContainsCi(string? haystack, string needle)
            => haystack != null && haystack.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;
    }
}
