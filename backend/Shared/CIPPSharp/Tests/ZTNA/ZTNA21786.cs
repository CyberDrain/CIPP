using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// User sign-in activity uses token protection.
    /// Port of Invoke-CippTestZTNA21786. Enabled CA policy scoped to Windows mobile/desktop clients for
    /// the two Office apps, with a secure sign-in session (token protection) control.
    /// </summary>
    public sealed class ZTNA21786 : ICippTest
    {
        private const string OfficeApp1 = "00000002-0000-0ff1-ce00-000000000000";
        private const string OfficeApp2 = "00000003-0000-0ff1-ce00-000000000000";

        public string Id => "ZTNA21786";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int count = 0;
            foreach (var p in Items(caPolicies))
            {
                if (!StrEq(p, "state", "enabled")) continue;

                var clientAppTypes = Nested(p, "conditions", "clientAppTypes");
                if (clientAppTypes.ValueKind != JsonValueKind.Array || clientAppTypes.GetArrayLength() != 1) continue;
                if (!ValEq(clientAppTypes[0], "mobileAppsAndDesktopClients")) continue;

                if (!ArrayContainsValue(Nested(p, "conditions", "applications", "includeApplications"), OfficeApp1)) continue;
                if (!ArrayContainsValue(Nested(p, "conditions", "applications", "includeApplications"), OfficeApp2)) continue;

                var platforms = Nested(p, "conditions", "platforms", "includePlatforms");
                if (platforms.ValueKind != JsonValueKind.Array || platforms.GetArrayLength() != 1) continue;
                if (!ValEq(platforms[0], "windows")) continue;

                if (!NestedTrue(p, "sessionControls", "secureSignInSession", "isEnabled")) continue;

                count++;
            }

            if (count > 0)
                return new CippTestResult(TestStatus.Passed, $"Found {count} token protection policies properly configured");

            return new CippTestResult(TestStatus.Failed, "No properly configured token protection policies found");
        }

        private static bool ArrayContainsValue(JsonElement arr, string value)
        {
            if (arr.ValueKind != JsonValueKind.Array) return false;
            foreach (var i in arr.EnumerateArray())
                if (string.Equals(AsString(i), value, System.StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
