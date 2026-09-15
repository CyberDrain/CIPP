using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe Links policies are tracking user clicks (TrackClicks == true).
    /// Port of Invoke-CippTestORCA156. Single source: ExoSafeLinksPolicies. Licensing is gated upstream by the engine.
    /// </summary>
    public sealed class ORCA156 : ICippTest
    {
        public string Id => "ORCA156";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoSafeLinksPolicies"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            var policies = Items(data.Get("ExoSafeLinksPolicies")).ToList();
            var failed = policies.Where(p => !IsTrue(p, "TrackClicks")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All Safe Links policies are tracking user clicks.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} Safe Links policies are not tracking user clicks.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "TrackClicks") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Track Clicks" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
