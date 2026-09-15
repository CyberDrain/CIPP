using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe Links is enabled for emails (EnableSafeLinksForEmail == true).
    /// Port of Invoke-CippTestORCA236. Single source: ExoSafeLinksPolicies. Licensing is gated upstream by the engine.
    /// </summary>
    public sealed class ORCA236 : ICippTest
    {
        public string Id => "ORCA236";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoSafeLinksPolicies"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            var policies = Items(data.Get("ExoSafeLinksPolicies")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "EnableSafeLinksForEmail")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All Safe Links policies have email protection enabled.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} Safe Links policies do not have email protection enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "EnableSafeLinksForEmail") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Enable Safe Links For Email" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
