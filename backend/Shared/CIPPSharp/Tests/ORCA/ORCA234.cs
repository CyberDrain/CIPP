using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Click through is disabled for Safe Documents (AllowSafeDocsOpen == false).
    /// Port of Invoke-CippTestORCA234. Single source: ExoAtpPolicyForO365 (first record). Licensing is
    /// gated upstream by the engine.
    /// </summary>
    public sealed class ORCA234 : ICippTest
    {
        public string Id => "ORCA234";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoAtpPolicyForO365"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            var policy = Items(data.Get("ExoAtpPolicyForO365")).First();

            // PS: $Policy.AllowSafeDocsOpen -eq $false → Passed. Missing/null is NOT -eq $false → Failed.
            if (IsFalse(policy, "AllowSafeDocsOpen"))
            {
                var sb = new StringBuilder();
                sb.Append("Click through is disabled for Safe Documents.\n\n");
                sb.Append($"**AllowSafeDocsOpen:** {CellOf(policy, "AllowSafeDocsOpen")}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("Click through is enabled for Safe Documents.\n\n");
            f.Append($"**AllowSafeDocsOpen:** {CellOf(policy, "AllowSafeDocsOpen")}");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
