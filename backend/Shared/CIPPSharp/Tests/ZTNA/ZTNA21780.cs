using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// No usage of ADAL in the tenant.
    /// Port of Invoke-CippTestZTNA21780. DirectoryRecommendations with recommendationType
    /// 'adalToMsalMigration'. Passed when none exist. (The PS here-string carries 12-space line
    /// indentation, reproduced verbatim; the parity gate is verdict, not the whitespace.)
    /// </summary>
    public sealed class ZTNA21780 : ICippTest
    {
        public string Id => "ZTNA21780";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var recs = data.Get("DirectoryRecommendations");
            if (!Any(recs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var adal = new List<JsonElement>();
            foreach (var r in Items(recs))
                if (StrEq(r, "recommendationType", "adalToMsalMigration")) adal.Add(r);

            if (adal.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No ADAL applications found in the tenant");

            var lines = new List<string>(adal.Count);
            foreach (var r in adal)
                lines.Add($"- {Text(r, "applicationDisplayName")} (AppId: {Text(r, "applicationId")})");

            var sb = new StringBuilder();
            sb.Append($"            Found {adal.Count} ADAL applications in the tenant that need migration to MSAL.\n");
            sb.Append("            ADAL Applications:\n");
            sb.Append("            ");
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
