using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.13.1 — Mailbox auditing SHALL be enabled.
    /// Port of Invoke-CippTestCISAMSEXO131. Passes when the org config's <c>AuditDisabled -eq $false</c>.
    /// </summary>
    public sealed class CISAMSEXO131 : ICippTest
    {
        public string Id => "CISAMSEXO131";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var config = data.Get("ExoOrganizationConfig");
            if (!Any(config))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.");

            var org = First(config);
            if (EqFalse(org, "AuditDisabled"))
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: Mailbox auditing is enabled for the organization.");

            var body = "❌ **Fail**: Mailbox auditing is disabled for the organization.\n\n"
                + "**Current Setting:**\n"
                + $"- AuditDisabled: {Cell(org, "AuditDisabled")}";
            return new CippTestResult(TestStatus.Failed, body);
        }
    }
}
