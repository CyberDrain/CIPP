using System.Collections.Generic;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// No exclusions for built-in protection. Port of Invoke-CippTestORCA239.
    /// Reads ExoAntiPhishPolicies (ExcludedSenders/ExcludedDomains) and ExoHostedContentFilterPolicy
    /// (AllowedSenders/AllowedSenderDomains); any exclusion bypasses built-in protection.
    /// </summary>
    public sealed class ORCA239 : ICippTest
    {
        public string Id => "ORCA239";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            bool hasPhish = data.Has("ExoAntiPhishPolicies");
            bool hasSpam = data.Has("ExoHostedContentFilterPolicy");

            if (!hasPhish && !hasSpam)
                return new CippTestResult(TestStatus.Skipped, "No policies found in database.");

            var issues = new List<string>();

            if (hasPhish)
            {
                foreach (var policy in Items(data.Get("ExoAntiPhishPolicies")))
                {
                    var details = new List<string>();
                    int senders = ArrayLen(policy, "ExcludedSenders");
                    int domains = ArrayLen(policy, "ExcludedDomains");
                    if (senders > 0) details.Add($"ExcludedSenders: {senders}");
                    if (domains > 0) details.Add($"ExcludedDomains: {domains}");
                    if (details.Count > 0)
                        issues.Add($"Anti-Phish Policy '{Str(policy, "Identity")}': {string.Join(", ", details)}");
                }
            }

            if (hasSpam)
            {
                foreach (var policy in Items(data.Get("ExoHostedContentFilterPolicy")))
                {
                    var details = new List<string>();
                    int senders = ArrayLen(policy, "AllowedSenders");
                    int domains = ArrayLen(policy, "AllowedSenderDomains");
                    if (senders > 0) details.Add($"AllowedSenders: {senders}");
                    if (domains > 0) details.Add($"AllowedSenderDomains: {domains}");
                    if (details.Count > 0)
                        issues.Add($"Anti-Spam Policy '{Str(policy, "Identity")}': {string.Join(", ", details)}");
                }
            }

            if (issues.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No exclusions found in built-in protection policies.");

            var f = new StringBuilder();
            f.Append($"Found {issues.Count} policies with exclusions that bypass built-in protection.\n\n");
            f.Append("**Issues Found:**\n\n");
            foreach (var issue in issues)
                f.Append($"- {issue}\n");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
