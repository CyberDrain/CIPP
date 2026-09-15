using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All user sign-in activity uses phishing-resistant authentication methods.
    /// Port of Invoke-CippTestZTNA21784. An enabled CA policy targeting all users must require an
    /// authentication strength whose allowed combinations are phishing-resistant, with no user
    /// exclusions.
    /// </summary>
    public sealed class ZTNA21784 : ICippTest
    {
        private static readonly string[] PhishMethods =
            { "windowsHelloForBusiness", "fido2", "x509CertificateMultiFactor", "certificateBasedAuthenticationPki" };

        public string Id => "ZTNA21784";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var authStrengths = data.Get("AuthenticationStrengths");

            var phishStrengthIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var s in Items(authStrengths))
            {
                bool phish = false;
                foreach (var combo in Arr(s, "allowedCombinations"))
                {
                    var c = AsString(combo);
                    if (c != null && Array.Exists(PhishMethods, m => string.Equals(m, c, StringComparison.OrdinalIgnoreCase)))
                    { phish = true; break; }
                }
                if (phish)
                {
                    var id = Str(s, "id");
                    if (id != null) phishStrengthIds.Add(id);
                }
            }

            if (phishStrengthIds.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No phishing-resistant authentication strength policies found in tenant");

            var relevant = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                if (!StrEq(p, "state", "enabled")) continue;
                bool allUsers = FlattenContains(p, "All", "conditions", "users", "includeUsers");
                var strengthId = NestedStr(p, "grantControls", "authenticationStrength", "id");
                if (allUsers && strengthId != null && phishStrengthIds.Contains(strengthId))
                    relevant.Add(p);
            }

            if (relevant.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "No Conditional Access policies found requiring phishing-resistant authentication for all users");

            var withExclusions = new List<JsonElement>();
            foreach (var p in relevant)
                if (ExcludeCount(p) > 0) withExclusions.Add(p);

            if (withExclusions.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"Found {relevant.Count} policies requiring phishing-resistant authentication, but {withExclusions.Count} have user exclusions creating coverage gaps:\n\n");
                var lines = new List<string>(withExclusions.Count);
                foreach (var p in withExclusions)
                    lines.Add($"- {Text(p, "displayName")} (Excludes {ExcludeCount(p)} users)");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Failed, sb.ToString());
            }
            else
            {
                var sb = new StringBuilder();
                sb.Append($"All users are protected by {relevant.Count} Conditional Access policies requiring phishing-resistant authentication:\n\n");
                var lines = new List<string>(relevant.Count);
                foreach (var p in relevant) lines.Add($"- {Text(p, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }
        }

        private static int ExcludeCount(JsonElement policy)
        {
            var ex = Nested(policy, "conditions", "users", "excludeUsers");
            return ex.ValueKind == JsonValueKind.Array ? ex.GetArrayLength() : 0;
        }
    }
}
