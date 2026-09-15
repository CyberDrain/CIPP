using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Data on iOS/iPadOS is protected by app protection policies.
    /// Port of Invoke-CippTestZTNA24548. IntuneAppProtectionManagedAppPolicies discriminated by
    /// URLName == 'iosManagedAppProtection'. Skip only when the type is absent; failure when data
    /// exists but no iOS policy.
    /// </summary>
    public sealed class ZTNA24548 : ICippTest
    {
        public string Id => "ZTNA24548";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var all = data.Get("IntuneAppProtectionManagedAppPolicies");
            if (!Any(all))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var ios = new List<JsonElement>();
            foreach (var p in Items(all))
                if (StrEq(p, "URLName", "iosManagedAppProtection")) ios.Add(p);

            if (ios.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ No iOS/iPadOS app protection policy exists in this tenant.\n\nApp protection policies were found for other platforms, so Intune data is being collected — there is simply no iOS policy.");

            bool passed = ios.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ At least one iOS app protection policy exists and is assigned.\n\n"
                : "❌ iOS app protection policies exist but none are assigned.\n\n");
            sb.Append("## iOS App Protection Policies\n\n");
            sb.Append("| Policy Name | Assigned |\n");
            sb.Append("| :---------- | :------- |\n");
            foreach (var p in ios)
                sb.Append($"| {Text(p, "displayName")} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
