using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Local account usage on Windows is restricted to reduce unauthorized access.
    /// Port of Invoke-CippTestZTNA24564. IntuneConfigurationPolicies on windows10 that configure the
    /// Local Users and Groups policy, and are assigned.
    /// </summary>
    public sealed class ZTNA24564 : ICippTest
    {
        private const string SettingId = "device_vendor_msft_policy_config_localusersandgroups_configure";

        public string Id => "ZTNA24564";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var windows = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (PropContains(p, "platforms", "windows10")) windows.Add(p);

            if (windows.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Windows policies found");

            var localUsers = new List<JsonElement>();
            foreach (var p in windows)
                if (FlattenStrings(p, "settings", "settingInstance", "settingDefinitionId").Contains(SettingId))
                    localUsers.Add(p);

            if (localUsers.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Local Users and Groups policy configured");

            int assigned = localUsers.FindAll(IsAssigned).Count;

            if (assigned > 0)
                return new CippTestResult(TestStatus.Passed,
                    $"At least one Local Users and Groups policy is configured and assigned. Found {assigned} assigned policy/policies");

            return new CippTestResult(TestStatus.Failed,
                $"Local Users and Groups policy exists but is not assigned. Found {localUsers.Count} unassigned policy/policies");
        }
    }
}
