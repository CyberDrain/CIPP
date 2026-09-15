using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Implement token protection policies.
    /// Port of Invoke-CippTestZTNA21941. Skipped on no ConditionalAccessPolicies data. Passed when an
    /// enabled Windows-platform CA policy enforces token protection (sign-in frequency
    /// primaryAndSecondaryAuthentication, or a secureSignIn/tokenProtection session control) and
    /// targets users plus the required Office 365 + Graph apps (or All apps).
    /// </summary>
    public sealed class ZTNA21941 : ICippTest
    {
        public string Id => "ZTNA21941";

        private static readonly string[] RequiredAppIds =
        {
            "00000002-0000-0ff1-ce00-000000000000", // Office 365 Exchange Online
            "00000003-0000-0ff1-ce00-000000000000", // Microsoft Graph
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped, "Unable to retrieve Conditional Access policies from cache.");

            // (name, state, hasUsers, hasRequiredApps, status)
            var tokenPolicies = new List<(string Name, string State, bool HasUsers, bool HasApps, string Status)>();

            foreach (var p in Items(policies))
            {
                bool hasWindows = FlattenContains(p, "windows", "conditions", "platforms", "includePlatforms")
                    || FlattenContains(p, "all", "conditions", "platforms", "includePlatforms");

                bool hasTokenProtection = false;
                var sc = Prop(p, "sessionControls");
                if (sc.ValueKind == JsonValueKind.Object)
                {
                    var sif = Prop(sc, "signInFrequency");
                    if (sif.ValueKind == JsonValueKind.Object
                        && IsTrue(sif, "isEnabled")
                        && StrEq(sif, "authenticationType", "primaryAndSecondaryAuthentication"))
                        hasTokenProtection = true;

                    if (!hasTokenProtection)
                    {
                        foreach (var prop in sc.EnumerateObject())
                        {
                            if ((prop.Name.IndexOf("secureSignIn", StringComparison.OrdinalIgnoreCase) >= 0
                                 || prop.Name.IndexOf("tokenProtection", StringComparison.OrdinalIgnoreCase) >= 0)
                                && prop.Value.ValueKind == JsonValueKind.Object
                                && IsTrue(prop.Value, "isEnabled"))
                            {
                                hasTokenProtection = true;
                                break;
                            }
                        }
                    }
                }

                if (hasWindows && hasTokenProtection && StrEq(p, "state", "enabled"))
                {
                    bool hasUsers = FlattenCount(p, "conditions", "users", "includeUsers") > 0;

                    bool hasRequiredApps = FlattenContains(p, "All", "conditions", "applications", "includeApplications");
                    if (!hasRequiredApps)
                    {
                        int found = 0;
                        foreach (var appId in RequiredAppIds)
                            if (FlattenContains(p, appId, "conditions", "applications", "includeApplications")) found++;
                        if (found == RequiredAppIds.Length) hasRequiredApps = true;
                    }

                    string status = (hasUsers && hasRequiredApps) ? "Pass"
                        : !hasUsers ? "No users targeted"
                        : !hasRequiredApps ? "Missing required apps"
                        : "Unknown";

                    tokenPolicies.Add((Text(p, "displayName"), Text(p, "state"), hasUsers, hasRequiredApps, status));
                }
            }

            int passing = 0;
            foreach (var tp in tokenPolicies) if (tp.Status == "Pass") passing++;
            bool passed = passing > 0;

            var sb = new StringBuilder();
            if (passed)
            {
                sb.Append("✅ **Pass**: Token protection policies are properly configured for Windows devices.\n\n");
                sb.Append("Token protection binds authentication tokens to devices, making stolen tokens unusable on other devices.\n\n");
            }
            else if (tokenPolicies.Count == 0)
            {
                sb.Append("❌ **Fail**: No token protection policies found for Windows devices.\n\n");
                sb.Append("Without token protection, authentication tokens can be stolen and replayed from other devices.\n\n");
                sb.Append("[Create token protection policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)");
            }
            else
            {
                sb.Append("❌ **Fail**: Token protection policies exist but are not properly configured.\n\n");
                sb.Append("Policies must target users and include both Office 365 and Microsoft Graph applications.\n\n");
            }

            if (tokenPolicies.Count > 0)
            {
                sb.Append("## Token protection policies\n\n");
                sb.Append("| Policy Name | State | Has Users | Has Required Apps | Status |\n");
                sb.Append("| :---------- | :---- | :-------- | :---------------- | :----- |\n");
                foreach (var tp in tokenPolicies)
                {
                    var stateIcon = string.Equals(tp.State, "enabled", StringComparison.OrdinalIgnoreCase) ? "✅" : "❌";
                    var usersIcon = tp.HasUsers ? "✅" : "❌";
                    var appsIcon = tp.HasApps ? "✅" : "❌";
                    var statusIcon = tp.Status == "Pass" ? "✅" : "❌";
                    sb.Append($"| {tp.Name} | {stateIcon} {tp.State} | {usersIcon} | {appsIcon} | {statusIcon} {tp.Status} |\n");
                }
                sb.Append("\n[Review policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
