using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant License Overview — informational summary of all licenses in the tenant.
    /// Port of Invoke-CippTestGenericTest001. Single source: LicenseOverview. Always Informational
    /// (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest001 : ICippTest
    {
        public string Id => "GenericTest001";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var licenseData = data.Get("LicenseOverview");
            if (!Any(licenseData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No license data found in the reporting database. Please sync the License Overview cache first.");
            }

            var licenses = licenseData.EnumerateArray().ToList();
            long totalLicenses = licenses.Sum(l => Int(l, "TotalLicenses"));
            long totalUsed = licenses.Sum(l => Int(l, "CountUsed"));
            double overallUtilization = totalLicenses > 0 ? Round1((double)totalUsed / totalLicenses * 100) : 0;

            var sb = new StringBuilder();
            sb.Append($"**Total Licenses:** {totalLicenses} | **In Use:** {totalUsed} | **Overall Utilization:** {Fmt(overallUtilization)}%\n\n");
            sb.Append("| License | In Use | Total | Available | Utilization |\n");
            sb.Append("|---------|--------|-------|-----------|-------------|\n");

            foreach (var license in licenses.OrderByDescending(l => Int(l, "TotalLicenses")))
            {
                var licName = Str(license, "License");
                long used = Int(license, "CountUsed");
                long total = Int(license, "TotalLicenses");
                long available = total - used;
                double util = total > 0 ? Round0((double)used / total * 100) : 0;
                // Verbatim from PS: the <70% branch also renders the green icon (original behaviour).
                string utilIcon = util >= 90 ? $"🟢 {Fmt(util)}%" : util >= 70 ? $"🟡 {Fmt(util)}%" : $"🟢 {Fmt(util)}%";
                sb.Append($"| {licName} | {used} | {total} | {available} | {utilIcon} |\n");
            }

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
