using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// User License Overview — which users have which licenses assigned.
    /// Port of Invoke-CippTestGenericTest002. Single source: LicenseOverview. Builds a UPN → licenses
    /// map from each SKU's AssignedUsers set. Always Informational (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest002 : ICippTest
    {
        private sealed class UserRow
        {
            public string Upn = "";
            public string? DisplayName;
            public List<string> Licenses = new();
        }

        public string Id => "GenericTest002";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var licenseData = data.Get("LicenseOverview");
            if (!Any(licenseData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No license data found in the reporting database. Please sync the License Overview cache first.");
            }

            // PS hashtable keys are case-insensitive; first-write-wins for DisplayName and key casing.
            var map = new Dictionary<string, UserRow>(StringComparer.OrdinalIgnoreCase);
            foreach (var license in licenseData.EnumerateArray())
            {
                var licenseName = Str(license, "License") ?? "";
                foreach (var user in RecordsOf(license, "AssignedUsers"))
                {
                    var upn = Str(user, "userPrincipalName");
                    if (string.IsNullOrEmpty(upn)) continue;
                    if (!map.TryGetValue(upn!, out var row))
                    {
                        row = new UserRow { Upn = upn!, DisplayName = Str(user, "displayName") };
                        map[upn!] = row;
                    }
                    row.Licenses.Add(licenseName);
                }
            }

            if (map.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No users with assigned licenses were found in the cached data.\n\nThis may indicate that the license data has not been synced recently, or no licenses have been assigned to individual users.");
            }

            var sb = new StringBuilder();
            sb.Append($"**Total Licensed Users:** {map.Count}\n\n");
            sb.Append("| User | Email | Licenses |\n");
            sb.Append("|------|-------|----------|\n");

            var sorted = map.Values.OrderBy(u => u.DisplayName ?? "", StringComparer.OrdinalIgnoreCase);
            int shown = 0;
            foreach (var entry in sorted)
            {
                var displayName = Markdown.EscapeCell(entry.DisplayName);
                var email = Markdown.EscapeCell(entry.Upn);
                var licList = string.Join(", ", entry.Licenses.OrderBy(x => x, StringComparer.OrdinalIgnoreCase));
                sb.Append($"| {displayName} | {email} | {licList} |\n");
                shown++;
                if (shown >= 500) break;
            }

            if (map.Count > 500)
                sb.Append($"\n*Showing 500 of {map.Count} licensed users.*\n");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
