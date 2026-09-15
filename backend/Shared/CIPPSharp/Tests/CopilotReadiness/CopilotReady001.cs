using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant has at least one Microsoft 365 Copilot prerequisite license.
    /// Port of Invoke-CippTestCopilotReady001. Single source: LicenseOverview.
    /// </summary>
    public sealed class CopilotReady001 : ICippTest
    {
        // Qualifying Copilot base-license service plans (all include Teams). -in is case-insensitive in PS.
        private static readonly HashSet<string> PrerequisiteServicePlans =
            new(System.StringComparer.OrdinalIgnoreCase) { "TEAMS1", "MCOSTANDARD" };

        public string Id => "CopilotReady001";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var licenseData = data.Get("LicenseOverview");
            if (licenseData.ValueKind != JsonValueKind.Array || licenseData.GetArrayLength() == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No license data found in database. Data collection may not yet have run for this tenant.");
            }

            var eligible = new List<JsonElement>();
            long assignableCount = 0;
            foreach (var sku in licenseData.EnumerateArray())
            {
                bool hasQualifying = false;
                foreach (var plan in Arr(sku, "ServicePlans"))
                {
                    var name = Str(plan, "servicePlanName");
                    if (name != null && PrerequisiteServicePlans.Contains(name)) { hasQualifying = true; break; }
                }
                if (hasQualifying && Int(sku, "TotalLicenses") > 0)
                {
                    eligible.Add(sku);
                    assignableCount += Int(sku, "TotalLicenses");
                }
            }

            if (eligible.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"Tenant has **{eligible.Count}** eligible prerequisite license plan(s) covering **{assignableCount}** seats that qualify for Microsoft 365 Copilot.\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var sku in eligible)
                    rows.Add(new[] { Cell(Prop(sku, "License")), Cell(Prop(sku, "TotalLicenses")), Cell(Prop(sku, "CountUsed")) });
                sb.Append(Markdown.Table(new[] { "License", "Total Seats", "Assigned" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var fail = new StringBuilder();
            fail.Append("No Microsoft 365 Copilot prerequisite licenses were found in this tenant.\n\n");
            fail.Append("Users must have an eligible M365 plan before a Copilot add-on license can be assigned. ");
            fail.Append("See [Microsoft licensing requirements](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-licensing) for the full list.");
            return new CippTestResult(TestStatus.Failed, fail.ToString());
        }
    }
}
