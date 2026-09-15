using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Named locations are configured.
    /// Port of Invoke-CippTestZTNA21865. Skipped on no NamedLocations data; Passed when at least one
    /// named location is trusted.
    /// </summary>
    public sealed class ZTNA21865 : ICippTest
    {
        public string Id => "ZTNA21865";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var locations = data.Get("NamedLocations");
            if (!Any(locations))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int total = locations.GetArrayLength();
            int trusted = 0;
            foreach (var l in Items(locations)) if (IsTrue(l, "isTrusted")) trusted++;
            bool passed = trusted > 0;

            var sb = new StringBuilder(passed
                ? "✅ Trusted named locations are configured.\n\n"
                : "❌ No trusted named locations configured.\n\n");
            sb.Append("## Named Locations\n\n");
            sb.Append($"{total} named locations found.\n\n");

            if (total > 0)
            {
                sb.Append("| Name | Type | Trusted |\n");
                sb.Append("| :--- | :--- | :------ |\n");
                foreach (var l in Items(locations))
                {
                    var type = StrEq(l, "@odata.type", "#microsoft.graph.ipNamedLocation") ? "IP-based"
                        : StrEq(l, "@odata.type", "#microsoft.graph.countryNamedLocation") ? "Country-based"
                        : "Unknown";
                    var trustedText = IsTrue(l, "isTrusted") ? "Yes" : "No";
                    sb.Append($"| {Text(l, "displayName")} | {type} | {trustedText} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
