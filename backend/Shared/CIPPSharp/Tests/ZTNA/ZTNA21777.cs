using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// App instance property lock is configured for all multitenant applications.
    /// Port of Invoke-CippTestZTNA21777. Multitenant Apps must have servicePrincipalLockConfiguration
    /// with isEnabled and allProperties both true.
    /// </summary>
    public sealed class ZTNA21777 : ICippTest
    {
        private static readonly string[] MultitenantAudiences =
            { "AzureADMultipleOrgs", "AzureADandPersonalMicrosoftAccount", "PersonalMicrosoftAccount" };

        public string Id => "ZTNA21777";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var apps = data.Get("Apps");
            if (!Any(apps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var multitenant = new List<JsonElement>();
            foreach (var a in Items(apps))
                if (PropIn(a, "signInAudience", MultitenantAudiences)) multitenant.Add(a);

            if (multitenant.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No multitenant applications found in the tenant.");

            var nonCompliant = new List<JsonElement>();
            foreach (var app in multitenant)
            {
                var lockCfg = Prop(app, "servicePrincipalLockConfiguration");
                bool enabled = lockCfg.ValueKind == JsonValueKind.Object
                    && IsTrue(lockCfg, "isEnabled") && IsTrue(lockCfg, "allProperties");
                if (!enabled) nonCompliant.Add(app);
            }

            if (nonCompliant.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {multitenant.Count} multitenant application(s) have property lock configured.");

            var sb = new StringBuilder();
            sb.Append($"{nonCompliant.Count} of {multitenant.Count} multitenant application(s) are missing property lock configuration.\n");
            sb.Append("\n");
            sb.Append("| Display Name | App ID | Sign-In Audience |\n");
            sb.Append("| :----------- | :----- | :--------------- |\n");
            int shown = 0;
            foreach (var app in nonCompliant)
            {
                if (shown >= 25) break;
                sb.Append($"| {Text(app, "displayName")} | {Text(app, "appId")} | {Text(app, "signInAudience")} |\n");
                shown++;
            }
            if (nonCompliant.Count > 25)
            {
                sb.Append("\n");
                sb.Append($"...and {nonCompliant.Count - 25} more.\n");
            }
            sb.Append("\n");
            sb.Append("**Remediation:** Configure `servicePrincipalLockConfiguration` with `isEnabled = true` and `allProperties = true` on each multitenant app to prevent unauthorized property modifications.");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
