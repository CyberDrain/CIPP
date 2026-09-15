using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.17.1 — Microsoft Purview Audit (Standard) logging SHALL be enabled.
    /// Port of Invoke-CippTestCISAMSEXO171. Passes when <c>UnifiedAuditLogIngestionEnabled -eq $true</c>.
    /// </summary>
    public sealed class CISAMSEXO171 : ICippTest
    {
        public string Id => "CISAMSEXO171";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var config = data.Get("ExoAdminAuditLogConfig");
            if (!Any(config))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.");

            var cfg = First(config);
            var value = Cell(cfg, "UnifiedAuditLogIngestionEnabled");
            if (EqTrue(cfg, "UnifiedAuditLogIngestionEnabled"))
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: Microsoft Purview Audit (Standard) logging is enabled.\n\n"
                    + "**Current Settings:**\n"
                    + $"- UnifiedAuditLogIngestionEnabled: {value}");

            return new CippTestResult(TestStatus.Failed,
                "❌ **Fail**: Microsoft Purview Audit (Standard) logging is not enabled.\n\n"
                + "**Current Settings:**\n"
                + $"- UnifiedAuditLogIngestionEnabled: {value}");
        }
    }
}
