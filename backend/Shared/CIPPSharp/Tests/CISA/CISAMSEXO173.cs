using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.17.3 — Audit logs SHALL be maintained for at least the minimum duration.
    /// Port of Invoke-CippTestCISAMSEXO173. Passes when <c>AdminAuditLogEnabled -eq $true</c>
    /// (admin audit log provides 1 year retention).
    /// </summary>
    public sealed class CISAMSEXO173 : ICippTest
    {
        public string Id => "CISAMSEXO173";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var config = data.Get("ExoAdminAuditLogConfig");
            if (!Any(config))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.");

            var cfg = First(config);
            var value = Cell(cfg, "AdminAuditLogEnabled");
            if (EqTrue(cfg, "AdminAuditLogEnabled"))
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: Admin audit log is enabled (provides 1 year retention).\n\n"
                    + "**Current Settings:**\n"
                    + $"- AdminAuditLogEnabled: {value}");

            return new CippTestResult(TestStatus.Failed,
                "❌ **Fail**: Admin audit log is not enabled.\n\n"
                + "**Current Settings:**\n"
                + $"- AdminAuditLogEnabled: {value}");
        }
    }
}
