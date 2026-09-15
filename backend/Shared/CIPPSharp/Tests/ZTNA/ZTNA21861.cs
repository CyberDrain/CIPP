using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All high-risk users are triaged.
    /// Port of Invoke-CippTestZTNA21861. Skipped on no RiskyUsers data; Passed when no user is both
    /// riskState 'atRisk' and riskLevel 'high'.
    /// </summary>
    public sealed class ZTNA21861 : ICippTest
    {
        public string Id => "ZTNA21861";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var riskyUsers = data.Get("RiskyUsers");
            if (!Any(riskyUsers))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var untriaged = new List<JsonElement>();
            foreach (var u in Items(riskyUsers))
                if (StrEq(u, "riskState", "atRisk") && StrEq(u, "riskLevel", "high")) untriaged.Add(u);

            if (untriaged.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ All high-risk users are properly triaged in Entra ID Protection.");

            var sb = new StringBuilder($"❌ Found **{untriaged.Count}** untriaged high-risk users in Entra ID Protection.\n\n");
            sb.Append("## Untriaged High-Risk Users\n\n");
            sb.Append("| User | Risk level | Last updated | Risk detail |\n");
            sb.Append("| :--- | :--- | :--- | :--- |\n");

            foreach (var u in untriaged)
            {
                var id = Text(u, "id");
                var upn = Str(u, "userPrincipalName");
                var display = string.IsNullOrEmpty(upn) ? id : upn;
                var portalLink = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/{id}";
                sb.Append($"| [{display}]({portalLink}) | {RiskLevelBadge(Str(u, "riskLevel"))} | {Text(u, "riskLastUpdatedDateTime")} | {Text(u, "riskDetail")} |\n");
            }

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
