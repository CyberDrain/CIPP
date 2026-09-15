using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Service principals do not have certificates or credentials associated with them.
    /// Port of Invoke-CippTestZTNA21896. Skipped on no ServicePrincipals data; Passed when no
    /// tenant-owned (non-Microsoft) service principal has password or key credentials. Otherwise
    /// returns the non-standard status 'Investigate' verbatim.
    /// </summary>
    public sealed class ZTNA21896 : ICippTest
    {
        public string Id => "ZTNA21896";
        private const string MicrosoftOwnerId = "f8cdef31-a31e-4b4a-93e4-5f571e91255a";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var sps = data.Get("ServicePrincipals");
            if (!Any(sps))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int passCount = 0, keyCount = 0;
            foreach (var sp in Items(sps))
            {
                bool notMicrosoft = !StrEq(sp, "appOwnerOrganizationId", MicrosoftOwnerId);
                if (ArrayLen(sp, "passwordCredentials") > 0 && notMicrosoft) passCount++;
                if (ArrayLen(sp, "keyCredentials") > 0 && notMicrosoft) keyCount++;
            }

            if (passCount == 0 && keyCount == 0)
                return new CippTestResult(TestStatus.Passed,
                    "Service principals do not have credentials associated with them");

            int total = passCount + keyCount;
            var lines = new List<string>
            {
                $"Found {total} service principal(s) with credentials configured in the tenant, which represents a security risk.",
                ""
            };

            if (passCount > 0)
            {
                lines.Add($"**Service principals with password credentials:** {passCount}");
                lines.Add("");
            }
            if (keyCount > 0)
            {
                lines.Add($"**Service principals with key credentials (certificates):** {keyCount}");
                lines.Add("");
            }

            lines.Add("**Security implications:**");
            lines.Add("- Service principals with credentials can be compromised if not properly secured");
            lines.Add("- Password credentials are less secure than managed identities or certificate-based authentication");
            lines.Add("- Consider using managed identities where possible to eliminate credential management");

            return new CippTestResult("Investigate", string.Join("\n", lines));
        }
    }
}
