using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Block legacy authentication policy is configured.
    /// Port of Invoke-CippTestZTNA21796. An enabled CA policy scoped to All users must block the
    /// exchangeActiveSync and other legacy client app types.
    /// </summary>
    public sealed class ZTNA21796 : ICippTest
    {
        public string Id => "ZTNA21796";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var blockPolicies = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                if (FlattenContains(p, "block", "grantControls", "builtInControls")
                    && FlattenContains(p, "exchangeActiveSync", "conditions", "clientAppTypes")
                    && FlattenContains(p, "other", "conditions", "clientAppTypes"))
                    blockPolicies.Add(p);
            }

            var enabledBlock = new List<JsonElement>();
            foreach (var p in blockPolicies)
                if (FlattenContains(p, "All", "conditions", "users", "includeUsers") && StrEq(p, "state", "enabled"))
                    enabledBlock.Add(p);

            if (enabledBlock.Count >= 1)
                return new CippTestResult(TestStatus.Passed,
                    $"Found {enabledBlock.Count} properly configured policies blocking legacy authentication:\n {OutString(enabledBlock)} ");

            if (blockPolicies.Count >= 1)
                return new CippTestResult(TestStatus.Failed,
                    $"Policies to block legacy authentication found but not properly configured or enabled: \n {OutString(blockPolicies)} ");

            return new CippTestResult(TestStatus.Failed, "No conditional access policies to block legacy authentication found");
        }

        // Mirror `$list | ForEach-Object { "- $name" } | Out-String`: lines joined with CRLF + trailing newline.
        private static string OutString(List<JsonElement> policies)
        {
            var sb = new StringBuilder();
            foreach (var p in policies) sb.Append($"- {Text(p, "displayName")}\r\n");
            return sb.ToString();
        }
    }
}
