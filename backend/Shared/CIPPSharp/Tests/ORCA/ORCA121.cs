using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Supported filter policy action used (ZAP-actionable SpamAction/PhishSpamAction).
    /// Port of Invoke-CippTestORCA121. Single source: ExoHostedContentFilterPolicy. Each of the two
    /// action settings is graded independently, so one policy can contribute multiple failures.
    /// </summary>
    public sealed class ORCA121 : ICippTest
    {
        public string Id => "ORCA121";

        private static readonly string[] SupportedActions = { "MoveToJmf", "Redirect", "Delete", "Quarantine" };
        private static readonly string[] Settings = { "SpamAction", "PhishSpamAction" };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            int policyCount = policies.Count;
            string supportedList = string.Join(", ", SupportedActions);

            var failures = new List<(string Policy, string Setting, string Value)>();
            foreach (var p in policies)
            {
                var policyName = Str(p, "Identity") ?? Str(p, "Name") ?? "";
                foreach (var setting in Settings)
                {
                    if (!InSet(p, setting, SupportedActions))
                    {
                        var raw = Str(p, setting);
                        var display = string.IsNullOrEmpty(raw) ? "Not set" : raw!;
                        failures.Add((policyName, setting, display));
                    }
                }
            }

            if (failures.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append($"✅ **Pass**: All {policyCount} anti-spam policy/policies use a filter action that Zero Hour Auto Purge supports.\n\n");
                sb.Append($"Supported actions: {supportedList}.");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"❌ **Fail**: {failures.Count} setting(s) across {policyCount} anti-spam policy/policies use an action that Zero Hour Auto Purge cannot act on:\n\n");
            var rows = failures.Select(x => (IReadOnlyList<string>)new[] { x.Policy, x.Setting, x.Value, supportedList }).ToList();
            f.Append(Markdown.Table(new[] { "Policy", "Setting", "Current Action", "Supported" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
