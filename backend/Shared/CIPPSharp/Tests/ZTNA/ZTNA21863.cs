using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All high-risk sign-ins are triaged.
    /// Port of Invoke-CippTestZTNA21863. Skipped on no RiskDetections data; Passed when no detection is
    /// both riskState 'atRisk' and riskLevel 'high'.
    /// </summary>
    public sealed class ZTNA21863 : ICippTest
    {
        public string Id => "ZTNA21863";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var detections = data.Get("RiskDetections");
            if (!Any(detections))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var untriaged = new List<JsonElement>();
            foreach (var d in Items(detections))
                if (StrEq(d, "riskState", "atRisk") && StrEq(d, "riskLevel", "high")) untriaged.Add(d);

            if (untriaged.Count == 0)
                return new CippTestResult(TestStatus.Passed, "✅ No untriaged risky sign ins in the tenant.");

            var sb = new StringBuilder($"❌ Found **{untriaged.Count}** untriaged high-risk sign ins.\n\n");
            sb.Append("## Untriaged High-Risk Sign ins\n\n");
            sb.Append("| Date | User Principal Name | Type | Risk Level |\n");
            sb.Append("| :---- | :---- | :---- | :---- |\n");

            foreach (var d in untriaged)
                sb.Append($"| {Text(d, "detectedDateTime")} | {Text(d, "userPrincipalName")} | {Text(d, "riskEventType")} | {RiskLevelBadge(Str(d, "riskLevel"))} |\n");

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
