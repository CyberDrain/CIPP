using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Senders are not being allow listed in an unsafe manner. Port of Invoke-CippTestORCA109.
    /// Single source: ExoHostedContentFilterPolicy. A policy fails if it has any AllowedSenders
    /// or AllowedSenderDomains.
    /// </summary>
    public sealed class ORCA109 : ICippTest
    {
        public string Id => "ORCA109";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => ArrayLen(p, "AllowedSenders") > 0 || ArrayLen(p, "AllowedSenderDomains") > 0).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("No anti-spam policies have sender allow lists configured.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies have sender allow lists configured.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[]
            {
                CellOf(p, "Identity"),
                ArrayLen(p, "AllowedSenders").ToString(CultureInfo.InvariantCulture),
                ArrayLen(p, "AllowedSenderDomains").ToString(CultureInfo.InvariantCulture)
            }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Allowed Senders", "Allowed Sender Domains" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
