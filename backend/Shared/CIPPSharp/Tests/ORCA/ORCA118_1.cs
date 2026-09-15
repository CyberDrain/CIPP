using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Domains not allow listed in Anti-Spam. Port of Invoke-CippTestORCA118_1.
    /// Single source: ExoHostedContentFilterPolicy. A policy fails if it has any AllowedSenderDomains.
    /// </summary>
    public sealed class ORCA118_1 : ICippTest
    {
        public string Id => "ORCA118_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => ArrayLen(p, "AllowedSenderDomains") > 0).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("No anti-spam policies have allowed sender domains configured.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies have allowed sender domains configured.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[]
            {
                CellOf(p, "Identity"),
                ArrayLen(p, "AllowedSenderDomains").ToString(CultureInfo.InvariantCulture)
            }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Allowed Sender Domains Count" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
