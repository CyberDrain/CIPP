using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe Attachments is enabled for SharePoint, OneDrive and Teams (EnableATPForSPOTeamsODB == true).
    /// Port of Invoke-CippTestORCA158. Single source: ExoAtpPolicyForO365 (first record). Licensing is
    /// gated upstream by the engine.
    /// </summary>
    public sealed class ORCA158 : ICippTest
    {
        public string Id => "ORCA158";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAtpPolicyForO365"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            var policy = Items(data.Get("ExoAtpPolicyForO365")).First();

            if (IsTrue(policy, "EnableATPForSPOTeamsODB"))
            {
                var sb = new StringBuilder();
                sb.Append("Safe Attachments is enabled for SharePoint, OneDrive, and Teams.\n\n");
                sb.Append($"**EnableATPForSPOTeamsODB:** {CellOf(policy, "EnableATPForSPOTeamsODB")}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("Safe Attachments is NOT enabled for SharePoint, OneDrive, and Teams.\n\n");
            f.Append($"**EnableATPForSPOTeamsODB:** {CellOf(policy, "EnableATPForSPOTeamsODB")}");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
