using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe Documents is enabled for Office clients (EnableSafeDocs == true).
    /// Port of Invoke-CippTestORCA225. Single source: ExoAtpPolicyForO365 (first record). Licensing is
    /// gated upstream by the engine.
    /// </summary>
    public sealed class ORCA225 : ICippTest
    {
        public string Id => "ORCA225";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAtpPolicyForO365"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            var policy = Items(data.Get("ExoAtpPolicyForO365")).First();

            if (IsTrue(policy, "EnableSafeDocs"))
            {
                var sb = new StringBuilder();
                sb.Append("Safe Documents is enabled for Office clients.\n\n");
                sb.Append($"**EnableSafeDocs:** {CellOf(policy, "EnableSafeDocs")}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("Safe Documents is NOT enabled for Office clients.\n\n");
            f.Append($"**EnableSafeDocs:** {CellOf(policy, "EnableSafeDocs")}");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
