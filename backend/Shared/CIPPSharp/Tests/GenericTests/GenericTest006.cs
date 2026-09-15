using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// User MFA Report — MFA posture for standard (non-admin) user accounts.
    /// Port of Invoke-CippTestGenericTest006. Single source: MFAState. Always Informational
    /// (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest006 : ICippTest
    {
        public string Id => "GenericTest006";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mfaData = data.Get("MFAState");
            if (!Any(mfaData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No MFA state data found in the reporting database. Please sync the MFA State cache first.");
            }

            var users = mfaData.EnumerateArray().Where(u => HasText(u, "UPN") && !IsTrue(u, "IsAdmin")).ToList();
            if (users.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No standard (non-admin) user accounts were found in the MFA state data.");
            }

            int total = users.Count;
            int mfaRegistered = 0, notProtected = 0;
            foreach (var u in users)
            {
                if (IsTrue(u, "MFARegistration")) mfaRegistered++;
                if (NotProtected(u)) notProtected++;
            }
            double mfaRegPct = total > 0 ? Round1((double)mfaRegistered / total * 100) : 0;

            var sb = new StringBuilder();
            sb.Append($"**Total Users:** {total} | **MFA Registered:** {mfaRegistered} ({Fmt(mfaRegPct)}%)");
            if (notProtected > 0) sb.Append($" | **Unprotected: {notProtected}**");
            sb.Append("\n\n");

            if (notProtected > 0)
                sb.Append($"**⚠️ {notProtected} user account(s) have no MFA enforcement.** Consider enabling a Conditional Access policy that requires MFA for all users.\n\n");

            sb.Append("| Display Name | MFA Registered | MFA Method | Protected By | User Type |\n");
            sb.Append("|-------------|----------------|------------|--------------|-----------|\n");

            foreach (var u in users.OrderBy(x => Str(x, "DisplayName") ?? "", StringComparer.OrdinalIgnoreCase).Take(100))
            {
                string name = EscapePipe(Str(u, "DisplayName"));
                string registered = IsTrue(u, "MFARegistration") ? "✅ Yes" : "❌ No";
                string methods = EscapePipe(FormatMfaMethods(u));
                string protection = ProtectionVerbose(u);
                string userType = StrEq(u, "UserType", "Guest") ? "Guest" : "Member";
                sb.Append($"| {name} | {registered} | {methods} | {protection} | {userType} |\n");
            }

            if (users.Count > 100)
                sb.Append($"\n*Showing 100 of {users.Count} user accounts.*\n");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
