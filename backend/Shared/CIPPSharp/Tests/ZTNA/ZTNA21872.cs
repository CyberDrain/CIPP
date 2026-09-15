using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Require multifactor authentication for device join and device registration using user action.
    /// Port of Invoke-CippTestZTNA21872. Skipped when either ConditionalAccessPolicies or
    /// DeviceRegistrationPolicy is missing. Passed only when device-registration CA policies exist that
    /// require MFA (built-in control or an authentication strength) and the tenant device setting does
    /// NOT force MFA on registration/join.
    /// </summary>
    public sealed class ZTNA21872 : ICippTest
    {
        public string Id => "ZTNA21872";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            var deviceReg = data.Get("DeviceRegistrationPolicy");

            const string skipMsg = "No data found in database. This may be due to missing required licenses or data collection not yet completed.";
            if (!Any(caPolicies)) return new CippTestResult(TestStatus.Skipped, skipMsg);
            if (!Any(deviceReg)) return new CippTestResult(TestStatus.Skipped, skipMsg);

            JsonElement drp = default;
            foreach (var d in Items(deviceReg)) { drp = d; break; }
            bool mfaInDeviceSettings = StrEq(drp, "multiFactorAuthConfiguration", "required");

            var deviceRegPolicies = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
                if (StrEq(p, "state", "enabled")
                    && FlattenContains(p, "urn:user:registerdevice", "conditions", "applications", "includeUserActions"))
                    deviceRegPolicies.Add(p);

            int validCount = 0;
            foreach (var p in deviceRegPolicies) if (RequiresMfa(p)) validCount++;

            string header;
            if (mfaInDeviceSettings)
                header = "❌ **MFA is configured incorrectly.** Device Settings has 'Require Multi-Factor Authentication to register or join devices' set to Yes. According to best practices, this should be set to No, and MFA should be enforced through Conditional Access policies instead.\n\n";
            else if (deviceRegPolicies.Count == 0)
                header = "❌ **No Conditional Access policies found** for device registration or device join. Create a policy that requires MFA for these user actions.\n\n";
            else if (validCount == 0)
                header = "❌ **Conditional Access policies found**, but they're not correctly configured. Policies should require MFA or appropriate authentication strength.\n\n";
            else
                header = "✅ **Properly configured Conditional Access policies found** that require MFA for device registration/join actions.\n\n";

            bool passed = !mfaInDeviceSettings && deviceRegPolicies.Count > 0 && validCount > 0;

            var sb = new StringBuilder(header);
            sb.Append("## Device Settings Configuration\n\n");
            sb.Append("| Setting | Value | Recommended Value | Status |\n");
            sb.Append("| :------ | :---- | :---------------- | :----- |\n");
            var devStatus = mfaInDeviceSettings ? "❌ Should be set to No" : "✅ Correctly configured";
            var devValue = mfaInDeviceSettings ? "Yes" : "No";
            sb.Append($"| Require Multi-Factor Authentication to register or join devices | {devValue} | No | {devStatus} |\n");

            if (deviceRegPolicies.Count > 0)
            {
                sb.Append("\n## Device Registration/Join Conditional Access Policies\n\n");
                sb.Append("| Policy Name | State | Requires MFA | Status |\n");
                sb.Append("| :---------- | :---- | :----------- | :----- |\n");
                foreach (var p in deviceRegPolicies)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/{Text(p, "id")}";
                    bool valid = RequiresMfa(p);
                    var mfaText = valid ? "Yes" : "No";
                    var status = valid ? "✅ Properly configured" : "❌ Incorrectly configured";
                    sb.Append($"| [{Text(p, "displayName")}]({link}) | {Text(p, "state")} | {mfaText} | {status} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        private static bool RequiresMfa(JsonElement policy)
            => FlattenContains(policy, "mfa", "grantControls", "builtInControls")
               || NestedExists(policy, "grantControls", "authenticationStrength");
    }
}
