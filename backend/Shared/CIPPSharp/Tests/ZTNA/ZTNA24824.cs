using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CA policies block access from noncompliant devices.
    /// Port of Invoke-CippTestZTNA24824. Skipped on no ConditionalAccessPolicies data; Failed when no
    /// enabled compliantDevice policy exists. Passed when compliantDevice policies cover all platforms
    /// (a single all-platforms policy, no platform filter, or windows+macOS+iOS+android combined).
    /// </summary>
    public sealed class ZTNA24824 : ICippTest
    {
        public string Id => "ZTNA24824";
        private static readonly string[] TrackedPlatforms = { "windows", "macOS", "iOS", "android" };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped, "Unable to retrieve Conditional Access policies from cache.");

            var compliantPolicies = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (StrEq(p, "state", "enabled")
                    && FlattenContains(p, "compliantDevice", "grantControls", "builtInControls"))
                    compliantPolicies.Add(p);

            if (compliantPolicies.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Fail**: No Conditional Access policies found that block access from noncompliant devices.\n\n"
                    + "[Create policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)");

            var coverage = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (var pf in TrackedPlatforms) coverage[pf] = false;
            bool allPlatformsPolicy = false;

            var details = new List<(string Name, string Platforms)>();
            foreach (var p in compliantPolicies)
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
                        foreach (var platform in platformList)
                            if (coverage.ContainsKey(platform)) coverage[platform] = true;
                    }
                }
                else
                {
                    allPlatformsPolicy = true;
                }
                details.Add((Text(p, "displayName"), platforms));
            }

            bool allCovered = allPlatformsPolicy
                || (coverage["windows"] && coverage["macOS"] && coverage["iOS"] && coverage["android"]);

            var sb = new StringBuilder();
            if (allCovered)
            {
                sb.Append("✅ **Pass**: Conditional Access policies block noncompliant devices across all platforms.\n\n");
            }
            else
            {
                sb.Append("❌ **Fail**: Conditional Access policies do not cover all device platforms.\n\n");
                var missing = new List<string>();
                foreach (var pf in TrackedPlatforms) if (!coverage[pf]) missing.Add(pf);
                if (missing.Count > 0)
                    sb.Append($"**Missing platform coverage**: {string.Join(", ", missing)}\n\n");
            }

            sb.Append("## Compliant device policies\n\n");
            sb.Append("| Policy Name | Platforms |\n");
            sb.Append("| :---------- | :-------- |\n");
            foreach (var d in details)
                sb.Append($"| {d.Name} | {d.Platforms} |\n");
            sb.Append("\n[Review policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)");

            return new CippTestResult(allCovered ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
