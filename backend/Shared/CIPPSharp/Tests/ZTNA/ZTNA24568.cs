using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Platform SSO is configured to strengthen authentication on macOS devices.
    /// Port of Invoke-CippTestZTNA24568. IntuneConfigurationPolicies (macOS/mdm/appleRemoteManagement)
    /// whose settings carry the Company Portal SSO extension identifier, and are assigned.
    /// </summary>
    public sealed class ZTNA24568 : ICippTest
    {
        private const string ExtensionIdSetting = "com.apple.extensiblesso_extensionidentifier";
        private const string ExtensionValue = "com.microsoft.CompanyPortalMac.ssoextension";

        public string Id => "ZTNA24568";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var macos = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (PropContains(p, "platforms", "macOS") && PropContains(p, "technologies", "mdm")
                    && PropContains(p, "technologies", "appleRemoteManagement"))
                    macos.Add(p);

            if (macos.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No macOS policies found");

            var sso = new List<JsonElement>();
            foreach (var p in macos)
            {
                bool match = false;
                foreach (var child in Flatten(p, "settings", "settingInstance", "groupSettingCollectionValue", "children"))
                {
                    if (StrEq(child, "settingDefinitionId", ExtensionIdSetting)
                        && string.Equals(NestedStr(child, "simpleSettingValue", "value"), ExtensionValue, System.StringComparison.OrdinalIgnoreCase))
                    {
                        match = true;
                        break;
                    }
                }
                if (match) sso.Add(p);
            }

            if (sso.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No macOS SSO policies configured with Microsoft Company Portal extension");

            int assigned = sso.FindAll(IsAssigned).Count;

            if (assigned > 0)
                return new CippTestResult(TestStatus.Passed,
                    $"macOS SSO policies are configured and assigned. Found {assigned} assigned policy/policies");

            return new CippTestResult(TestStatus.Failed,
                $"macOS SSO policy exists but is not assigned. Found {sso.Count} unassigned policy/policies");
        }
    }
}
