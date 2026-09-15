using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe attachments unknown malware response set to block messages (Action in Block/Quarantine).
    /// Port of Invoke-CippTestORCA124. Single source: ExoSafeAttachmentPolicies. Licensing is gated
    /// upstream by the engine.
    /// </summary>
    public sealed class ORCA124 : ICippTest
    {
        public string Id => "ORCA124";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoSafeAttachmentPolicies"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            var policies = Items(data.Get("ExoSafeAttachmentPolicies")).ToList();
            var failed = policies.Where(p => !InSet(p, "Action", "Block", "Quarantine")).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All Safe Attachments policies have unknown malware response set to Block.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} Safe Attachments policies do not have unknown malware response set to Block.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "Action") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Action" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
