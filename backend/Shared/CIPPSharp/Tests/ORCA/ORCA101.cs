using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Bulk is marked as spam (MarkAsSpamBulkMail = On). Port of Invoke-CippTestORCA101.
    /// Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA101 : ICippTest
    {
        public string Id => "ORCA101";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var passed = policies.Where(p => StrEq(p, "MarkAsSpamBulkMail", "On")).ToList();
            var failed = policies.Where(p => !StrEq(p, "MarkAsSpamBulkMail", "On")).ToList();

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies are configured to mark bulk mail as spam.\n\n");
                sb.Append($"**Compliant Policies:** {passed.Count}\n\n");
                if (passed.Count > 0)
                {
                    var rows = passed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "MarkAsSpamBulkMail") }).ToList();
                    sb.Append(Markdown.Table(new[] { "Policy Name", "Mark As Spam Bulk Mail" }, rows));
                }
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies are not configured to mark bulk mail as spam.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var frows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "MarkAsSpamBulkMail") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Mark As Spam Bulk Mail" }, frows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
