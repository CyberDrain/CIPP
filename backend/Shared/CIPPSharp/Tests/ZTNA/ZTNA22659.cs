using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Triage risky workload identity sign-ins.
    /// Port of Invoke-CippTestZTNA22659. Skipped on no ServicePrincipalRiskDetections data; Passed when
    /// no detection has activity 'signIn' and riskState 'atRisk'.
    /// </summary>
    public sealed class ZTNA22659 : ICippTest
    {
        public string Id => "ZTNA22659";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var detections = data.Get("ServicePrincipalRiskDetections");
            if (!Any(detections))
                return new CippTestResult(TestStatus.Skipped,
                    "Unable to retrieve service principal risk detections from cache.");

            var risky = new List<JsonElement>();
            foreach (var d in Items(detections))
                if (StrEq(d, "activity", "signIn") && StrEq(d, "riskState", "atRisk")) risky.Add(d);

            if (risky.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: No risky workload identity sign-ins detected or all have been triaged.\n\n"
                    + "[View identity protection](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyServicePrincipals)");

            var sb = new StringBuilder($"❌ **Fail**: There are {risky.Count} risky workload identity sign-in(s) that require investigation.\n\n");
            sb.Append("## Risky service principal sign-ins\n\n");
            sb.Append("| Service Principal | App ID | Risk State | Risk Level | Last Updated |\n");
            sb.Append("| :---------------- | :----- | :--------- | :--------- | :----------- |\n");

            foreach (var d in risky)
            {
                var spName = string.IsNullOrEmpty(Str(d, "servicePrincipalDisplayName")) ? "N/A" : Str(d, "servicePrincipalDisplayName");
                var appId = string.IsNullOrEmpty(Str(d, "appId")) ? "N/A" : Str(d, "appId");
                var riskState = string.IsNullOrEmpty(Str(d, "riskState")) ? "N/A" : Str(d, "riskState");
                var riskLevel = string.IsNullOrEmpty(Str(d, "riskLevel")) ? "N/A" : Str(d, "riskLevel");
                var lastRaw = Str(d, "lastUpdatedDateTime");
                var lastUpdated = string.IsNullOrEmpty(lastRaw) ? "N/A" : FormatDate(lastRaw!);
                sb.Append($"| {spName} | {appId} | {riskState} | {riskLevel} | {lastUpdated} |\n");
            }

            sb.Append("\n[Investigate and remediate](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyServicePrincipals)");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
