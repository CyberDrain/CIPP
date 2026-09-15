using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Licensed User MFA Report — MFA posture for licensed users only.
    /// Port of Invoke-CippTestGenericTest007. Single source: MFAState. Always Informational
    /// (Skipped when the cache is empty). Note: this report does not pipe-escape its cells (matches PS).
    /// </summary>
    public sealed class GenericTest007 : ICippTest
    {
        public string Id => "GenericTest007";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mfaData = data.Get("MFAState");
            if (!Any(mfaData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No MFA state data found in the reporting database. Please sync the MFA State cache first.");
            }

            var users = mfaData.EnumerateArray().Where(u => HasText(u, "UPN") && IsTrue(u, "isLicensed")).ToList();
            if (users.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No licensed user accounts were found in the MFA state data. This may indicate no licenses have been assigned or the data needs to be re-synced.");
            }

            int total = users.Count;
            int mfaRegistered = 0, notProtected = 0, admins = 0;
            foreach (var u in users)
            {
                if (IsTrue(u, "MFARegistration")) mfaRegistered++;
                if (NotProtected(u)) notProtected++;
                if (IsTrue(u, "IsAdmin")) admins++;
            }
            double mfaRegPct = total > 0 ? Round1((double)mfaRegistered / total * 100) : 0;

            var sb = new StringBuilder();
            sb.Append($"**Licensed Users:** {total} | **Admins among them:** {admins} | **MFA Registered:** {mfaRegistered} ({Fmt(mfaRegPct)}%)");
            if (notProtected > 0) sb.Append($" | **Unprotected: {notProtected}**");
            sb.Append("\n\n");

            if (notProtected > 0)
                sb.Append($"**⚠️ {notProtected} licensed user(s) have no MFA enforcement.** These accounts have access to company data and email but are not protected by any MFA policy.\n\n");

            sb.Append("| Display Name | Role | MFA Registered | MFA Method | Protected By |\n");
            sb.Append("|-------------|------|----------------|------------|--------------|\n");

            foreach (var u in users.OrderBy(x => Str(x, "DisplayName") ?? "", StringComparer.OrdinalIgnoreCase).Take(100))
            {
                string name = Str(u, "DisplayName") ?? "";
                string role = IsTrue(u, "IsAdmin") ? "🔑 Admin" : "User";
                string registered = IsTrue(u, "MFARegistration") ? "✅ Yes" : "❌ No";
                string methods = FormatMfaMethods(u);
                string protection = ProtectionVerbose(u);
                sb.Append($"| {name} | {role} | {registered} | {methods} | {protection} |\n");
            }

            if (users.Count > 100)
                sb.Append($"\n*Showing 100 of {users.Count} licensed user accounts.*\n");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
