using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (1.8) — Data encrypted at rest via an assigned Windows BitLocker policy. Port of
    /// Invoke-CippTestSMB1001_1_8. Single source: IntuneConfigurationPolicies, detecting the
    /// 'device_vendor_msft_bitlocker_requiredeviceencryption_1' choice value (ZTNA24550 pattern).
    /// </summary>
    public sealed class SMB1001_1_8 : ICippTest
    {
        private const string BitLockerValue = "device_vendor_msft_bitlocker_requiredeviceencryption_1";

        public string Id => "SMB1001_1_8";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "IntuneConfigurationPolicies cache not found. This may be due to missing Intune licenses or data collection not yet completed.");
            }

            var bitlocker = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!Contains(Str(p, "platforms"), "windows10")) continue;
                var values = Chain(p, "settings", "settingInstance", "choiceSettingValue", "value");
                if (values.Any(v => ValEq(v, BitLockerValue))) bitlocker.Add(p);
            }

            int assigned = bitlocker.Count(HasAssignments);

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append("At least one Windows BitLocker policy is configured and assigned.\n\n");
                sb.Append("**Windows BitLocker Policies:**\n\n");
                var rows = new List<IReadOnlyList<string>>();
                foreach (var p in bitlocker)
                {
                    var status = HasAssignments(p) ? "✅ Assigned" : "❌ Not assigned";
                    rows.Add(new[] { CellOf(p, "name"), status, AssignmentCount(p).ToString() });
                }
                sb.Append(Markdown.Table(new[] { "Policy Name", "Status", "Assignment Count" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }

            if (bitlocker.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append("Windows BitLocker policies exist but none are assigned.\n\n");
                sb.Append("**Unassigned BitLocker Policies:**\n\n");
                foreach (var p in bitlocker) sb.Append($"- {Str(p, "name") ?? ""}\n");
                return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
            }

            return new CippTestResult(TestStatus.Failed, "No Windows BitLocker policy is configured.");
        }
    }
}
