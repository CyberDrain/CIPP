using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.1.4) — Administrative accounts SHALL use licenses with a reduced application
    /// footprint. Port of Invoke-CippTestCIS_1_1_4. Fails licensed admins with an Enabled
    /// productivity workload (Exchange/SharePoint/Teams/Skype).
    /// </summary>
    public sealed class CIS_1_1_4 : ICippTest
    {
        private static readonly HashSet<string> ProductivityServices = new(StringComparer.OrdinalIgnoreCase)
        {
            "exchange", "SharePoint", "MicrosoftCommunicationsOnline", "TeamspaceAPI",
        };

        public string Id => "CIS_1_1_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privRoles = GetPrivilegedRoles(data);
            var users = data.Get("Users");

            if (privRoles.Count == 0 || !Any(users))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Roles or Users) not found. Please refresh the cache for this tenant.");
            }

            var privUserIds = CollectPrivilegedUserIds(data);
            var privilegedUsers = UsersByIds(data, privUserIds);

            var licensedAdmins = new List<JsonElement>();
            foreach (var u in privilegedUsers)
                if (ArrayCount(u, "assignedLicenses") > 0) licensedAdmins.Add(u);

            var nonCompliant = new List<JsonElement>();
            foreach (var u in licensedAdmins)
            {
                bool hasProductivity = false;
                foreach (var plan in Arr(u, "assignedPlans"))
                {
                    var svc = Str(plan, "service");
                    if (svc != null && ProductivityServices.Contains(svc) && StrEq(plan, "capabilityStatus", "Enabled"))
                    {
                        hasProductivity = true;
                        break;
                    }
                }
                if (hasProductivity) nonCompliant.Add(u);
            }

            if (licensedAdmins.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No privileged users have licenses assigned.");

            if (nonCompliant.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {licensedAdmins.Count} licensed privileged user(s) hold only identity-only licenses (no productivity workloads enabled).");
            }

            var sb = new StringBuilder();
            sb.Append($"{nonCompliant.Count} privileged user(s) have productivity workloads (Exchange/SharePoint/Teams/Skype) enabled on their administrative accounts.\n\n");
            var lines = new List<string>();
            int shown = 0;
            foreach (var u in nonCompliant)
            {
                if (shown++ >= 25) break;
                lines.Add($"- {Str(u, "userPrincipalName")}");
            }
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
