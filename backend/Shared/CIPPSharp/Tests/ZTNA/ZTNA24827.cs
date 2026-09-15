using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CA policies block unmanaged mobile apps.
    /// Port of Invoke-CippTestZTNA24827. Skipped on no ConditionalAccessPolicies data; Failed when no
    /// enabled compliantApplication policy targets mobile. Passed when both iOS and Android are covered
    /// (an all-platforms policy, no platform filter, or both platforms combined).
    /// </summary>
    public sealed class ZTNA24827 : ICippTest
    {
        public string Id => "ZTNA24827";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped, "Unable to retrieve Conditional Access policies from cache.");

            var compliantAppPolicies = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!(StrEq(p, "state", "enabled")
                      && FlattenContains(p, "compliantApplication", "grantControls", "builtInControls")))
                    continue;

                var platformList = FlattenStrings(p, "conditions", "platforms", "includePlatforms");
                bool appliesToMobile;
                if (platformList.Count > 0)
                    appliesToMobile = platformList.Exists(x =>
                        string.Equals(x, "all", StringComparison.OrdinalIgnoreCase)
                        || string.Equals(x, "iOS", StringComparison.OrdinalIgnoreCase)
                        || string.Equals(x, "android", StringComparison.OrdinalIgnoreCase));
                else
                    appliesToMobile = true;

                if (appliesToMobile) compliantAppPolicies.Add(p);
            }

            if (compliantAppPolicies.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Fail**: No Conditional Access policies found that block unmanaged mobile apps.\n\n"
                    + "[Create policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)");

            bool iosCovered = false, androidCovered = false, allPlatformsPolicy = false;
            var details = new List<(string Name, string Platforms)>();

            foreach (var p in compliantAppPolicies)
            {
                var platformList = FlattenStrings(p, "conditions", "platforms", "includePlatforms");
                string platforms = "All platforms";
                if (platformList.Count > 0)
                {
                    if (platformList.Exists(x => string.Equals(x, "all", StringComparison.OrdinalIgnoreCase)))
                    {
                        allPlatformsPolicy = true;
                        platforms = "All platforms";
                    }
                    else
                    {
                        platforms = string.Join(", ", platformList);
                        if (platformList.Exists(x => string.Equals(x, "iOS", StringComparison.OrdinalIgnoreCase))) iosCovered = true;
                        if (platformList.Exists(x => string.Equals(x, "android", StringComparison.OrdinalIgnoreCase))) androidCovered = true;
                    }
                }
                else
                {
                    allPlatformsPolicy = true;
                }
                details.Add((Text(p, "displayName"), platforms));
            }

            bool bothCovered = allPlatformsPolicy || (iosCovered && androidCovered);

            var sb = new StringBuilder();
            if (bothCovered)
            {
                sb.Append("✅ **Pass**: Conditional Access policies block unmanaged apps on both iOS and Android platforms.\n\n");
            }
            else
            {
                sb.Append("❌ **Fail**: Conditional Access policies do not cover all mobile platforms.\n\n");
                var missing = new List<string>();
                if (!iosCovered) missing.Add("iOS");
                if (!androidCovered) missing.Add("android");
                if (missing.Count > 0)
                    sb.Append($"**Missing platform coverage**: {string.Join(", ", missing)}\n\n");
            }

            sb.Append("## Compliant application policies\n\n");
            sb.Append("| Policy Name | Platforms |\n");
            sb.Append("| :---------- | :-------- |\n");
            foreach (var d in details)
                sb.Append($"| {d.Name} | {d.Platforms} |\n");
            sb.Append("\n[Review policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)");

            return new CippTestResult(bothCovered ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
