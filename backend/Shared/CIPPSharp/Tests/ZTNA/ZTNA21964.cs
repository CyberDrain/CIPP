using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Enable protected actions to secure Conditional Access policy creation and changes.
    /// Port of Invoke-CippTestZTNA21964. Skipped on no AuthenticationStrengths data; otherwise always
    /// Passed with an informational breakdown of built-in vs custom authentication strengths.
    /// </summary>
    public sealed class ZTNA21964 : ICippTest
    {
        public string Id => "ZTNA21964";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var strengths = data.Get("AuthenticationStrengths");
            if (!Any(strengths))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int total = strengths.GetArrayLength();
            var builtIn = new List<JsonElement>();
            var custom = new List<JsonElement>();
            foreach (var s in Items(strengths))
            {
                if (StrEq(s, "policyType", "builtIn")) builtIn.Add(s);
                if (StrEq(s, "policyType", "custom")) custom.Add(s);
            }

            var sb = new StringBuilder("## Authentication Strength Policies\n\n");
            sb.Append($"Found {total} authentication strength policies ({builtIn.Count} built-in, {custom.Count} custom).\n\n");

            if (custom.Count > 0)
            {
                sb.Append("### Custom Authentication Strengths\n\n");
                sb.Append("| Name | Combinations |\n");
                sb.Append("| :--- | :---------- |\n");
                foreach (var s in custom)
                {
                    int combinations = ArrayLen(s, "allowedCombinations");
                    sb.Append($"| {Text(s, "displayName")} | {combinations} methods |\n");
                }
            }

            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }
    }
}
