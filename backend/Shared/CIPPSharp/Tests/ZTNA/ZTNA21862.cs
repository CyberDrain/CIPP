using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All risky workload identities are triaged.
    /// Port of Invoke-CippTestZTNA21862. Skipped when there are no untriaged risky service principals
    /// AND no service principal risk detections at all. Passed when neither untriaged set has entries.
    /// </summary>
    public sealed class ZTNA21862 : ICippTest
    {
        public string Id => "ZTNA21862";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var rawPrincipals = data.Get("RiskyServicePrincipals");
            var rawDetections = data.Get("ServicePrincipalRiskDetections");

            var untriagedPrincipals = new List<JsonElement>();
            foreach (var sp in Items(rawPrincipals))
                if (StrEq(sp, "riskState", "atRisk")) untriagedPrincipals.Add(sp);

            var untriagedDetections = new List<JsonElement>();
            foreach (var d in Items(rawDetections))
                if (StrEq(d, "riskState", "atRisk")) untriagedDetections.Add(d);

            if (untriagedPrincipals.Count == 0 && !Any(rawDetections))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            if (untriagedPrincipals.Count == 0 && untriagedDetections.Count == 0)
                return new CippTestResult(TestStatus.Passed, "✅ All risky workload identities have been triaged");

            var sb = new StringBuilder(
                $"❌ Found {untriagedPrincipals.Count} untriaged risky service principals and {untriagedDetections.Count} untriaged risk detections\n\n");

            if (untriagedPrincipals.Count > 0)
            {
                sb.Append("## Untriaged Risky Service Principals\n\n");
                sb.Append("| Service Principal | Type | Risk Level | Risk State | Risk Last Updated |\n");
                sb.Append("| :--- | :--- | :--- | :--- | :--- |\n");
                foreach (var sp in untriagedPrincipals)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/SignOn/objectId/{Text(sp, "id")}/appId/{Text(sp, "appId")}";
                    sb.Append($"| [{Text(sp, "displayName")}]({link}) | {Text(sp, "servicePrincipalType")} | {RiskLevelBadge(Str(sp, "riskLevel"))} | {RiskStateBadge(Str(sp, "riskState"))} | {Text(sp, "riskLastUpdatedDateTime")} |\n");
                }
            }

            if (untriagedDetections.Count > 0)
            {
                sb.Append("\n\n## Untriaged Risk Detection Events\n\n");
                sb.Append("| Service Principal | Risk Level | Risk State | Risk Event Type | Risk Last Updated |\n");
                sb.Append("| :--- | :--- | :--- | :--- | :--- |\n");
                foreach (var d in untriagedDetections)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/SignOn/objectId/{Text(d, "servicePrincipalId")}/appId/{Text(d, "appId")}";
                    sb.Append($"| [{Text(d, "servicePrincipalDisplayName")}]({link}) | {RiskLevelBadge(Str(d, "riskLevel"))} | {RiskStateBadge(Str(d, "riskState"))} | {Text(d, "riskEventType")} | {Text(d, "detectedDateTime")} |\n");
                }
            }

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
