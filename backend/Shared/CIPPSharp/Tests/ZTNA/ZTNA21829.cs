using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Use cloud authentication.
    /// Port of Invoke-CippTestZTNA21829. Fails if any domain uses Federated authentication.
    /// </summary>
    public sealed class ZTNA21829 : ICippTest
    {
        public string Id => "ZTNA21829";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var domains = data.Get("Domains");
            if (!Any(domains))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var federated = new List<JsonElement>();
            foreach (var d in Items(domains))
                if (StrEq(d, "authenticationType", "Federated")) federated.Add(d);

            if (federated.Count == 0)
                return new CippTestResult(TestStatus.Passed, "All domains are using cloud authentication.\n\n");

            var sb = new StringBuilder("Federated authentication is in use.\n\n");
            sb.Append("\n## List of federated domains\n\n");
            sb.Append("| Domain Name |\n");
            sb.Append("| :--- |\n");
            foreach (var d in federated) sb.Append($"| {Text(d, "id")} |\n");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
