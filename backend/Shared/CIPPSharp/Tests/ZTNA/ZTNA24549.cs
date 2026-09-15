using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Data on Android is protected by app protection policies.
    /// Port of Invoke-CippTestZTNA24549. IntuneAppProtectionManagedAppPolicies discriminated by
    /// URLName == 'androidManagedAppProtection'.
    /// </summary>
    public sealed class ZTNA24549 : ICippTest
    {
        public string Id => "ZTNA24549";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var all = data.Get("IntuneAppProtectionManagedAppPolicies");
            if (!Any(all))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var android = new List<JsonElement>();
            foreach (var p in Items(all))
                if (StrEq(p, "URLName", "androidManagedAppProtection")) android.Add(p);

            if (android.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ No Android app protection policy exists in this tenant.\n\nApp protection policies were found for other platforms, so Intune data is being collected — there is simply no Android policy.");

            bool passed = android.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one Android app protection policy exists and is assigned.\n\n"
                : "❌ Android app protection policies exist but none are assigned.\n\n");
            sb.Append("## Android App Protection Policies\n\n");
            sb.Append("| Policy Name | Assigned |\n");
            sb.Append("| :---------- | :------- |\n");
            foreach (var p in android)
                sb.Append($"| {Text(p, "displayName")} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
