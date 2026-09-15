using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Data on Windows is protected by BitLocker encryption.
    /// Port of Invoke-CippTestZTNA24550. IntuneConfigurationPolicies for platform windows10 whose
    /// settings choice value enables required device encryption; Passed if at least one is assigned.
    /// </summary>
    public sealed class ZTNA24550 : ICippTest
    {
        private const string RequiredValue = "device_vendor_msft_bitlocker_requiredeviceencryption_1";

        public string Id => "ZTNA24550";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matching = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!PropContains(p, "platforms", "windows10")) continue;
                if (FlattenContains(p, RequiredValue, "settings", "settingInstance", "choiceSettingValue", "value"))
                    matching.Add(p);
            }

            int assigned = matching.FindAll(IsAssigned).Count;

            if (assigned > 0)
            {
                var sb = new StringBuilder();
                sb.Append("At least one Windows BitLocker policy is configured and assigned.\n");
                sb.Append("\n**Windows BitLocker Policies:**\n\n");
                sb.Append("| Policy Name | Status | Assignment Count |\n");
                sb.Append("| :---------- | :----- | :--------------- |\n");
                foreach (var p in matching)
                {
                    var status = IsAssigned(p) ? "✅ Assigned" : "❌ Not assigned";
                    sb.Append($"| {Text(p, "name")} | {status} | {ArrayLen(p, "assignments")} |\n");
                }
                return new CippTestResult(TestStatus.Passed, sb.ToString().TrimEnd('\n'));
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append("Windows BitLocker policies exist but none are assigned.\n");
                sb.Append("\n**Unassigned BitLocker Policies:**\n\n");
                foreach (var p in matching) sb.Append($"- {Text(p, "name")}\n");
                return new CippTestResult(TestStatus.Failed, sb.ToString().TrimEnd('\n'));
            }

            return new CippTestResult(TestStatus.Failed, "No Windows BitLocker policy is configured or assigned.");
        }
    }
}
