using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Own domains not allow listed in Anti-Spam. Port of Invoke-CippTestORCA118_3.
    /// Joins ExoHostedContentFilterPolicy with ExoAcceptedDomains: a policy fails if any of the
    /// tenant's own accepted domains appears in its AllowedSenderDomains.
    /// </summary>
    public sealed class ORCA118_3 : ICippTest
    {
        public string Id => "ORCA118_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            if (!data.Has("ExoAcceptedDomains"))
                return new CippTestResult(TestStatus.Skipped, "No accepted domains found in database.");

            var ownDomains = new HashSet<string>(
                Items(data.Get("ExoAcceptedDomains")).Select(d => Str(d, "DomainName") ?? "").Where(s => s.Length > 0),
                StringComparer.OrdinalIgnoreCase);

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = new List<(System.Text.Json.JsonElement Policy, List<string> Own)>();
            int passedCount = 0;

            foreach (var p in policies)
            {
                var ownInList = StringValues(p, "AllowedSenderDomains").Where(d => ownDomains.Contains(d)).ToList();
                if (ownInList.Count > 0) failed.Add((p, ownInList));
                else passedCount++;
            }

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("No anti-spam policies have own domains in the allow list.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies have own domains in the allow list.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(x => (IReadOnlyList<string>)new[] { CellOf(x.Policy, "Identity"), string.Join(", ", x.Own) }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Own Domains in Allow List" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
