using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Admin MFA Report — MFA posture for administrator accounts only.
    /// Port of Invoke-CippTestGenericTest005. Single source: MFAState. Always Informational
    /// (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest005 : ICippTest
    {
        public string Id => "GenericTest005";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mfaData = data.Get("MFAState");
            if (!Any(mfaData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No MFA state data found in the reporting database. Please sync the MFA State cache first.");
            }

            var admins = mfaData.EnumerateArray().Where(u => HasText(u, "UPN") && IsTrue(u, "IsAdmin")).ToList();
            if (admins.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "No administrator accounts were found in the MFA state data. This is unusual and may indicate the data needs to be re-synced.");
            }

            int total = admins.Count;
            int mfaRegistered = 0, notProtected = 0;
            foreach (var a in admins)
            {
                if (IsTrue(a, "MFARegistration")) mfaRegistered++;
                if (NotProtected(a)) notProtected++;
            }
            double mfaRegPct = total > 0 ? Round1((double)mfaRegistered / total * 100) : 0;

            var sb = new StringBuilder();
            sb.Append($"**Total Admins:** {total} | **MFA Registered:** {mfaRegistered} ({Fmt(mfaRegPct)}%)");
            if (notProtected > 0) sb.Append($" | **⚠️ Unprotected: {notProtected}**");
            sb.Append("\n\n");

            if (notProtected > 0)
                sb.Append($"**🔴 Critical: {notProtected} admin account(s) have no MFA enforcement.** Admin accounts without MFA are the #1 target for attackers. This should be addressed immediately.\n\n");
            else if (mfaRegistered == total)
                sb.Append("**✅ All admin accounts have MFA registered and enforced.** Great job keeping your most privileged accounts secured.\n\n");

            sb.Append("| Display Name | MFA Registered | MFA Method | Protected By | Account Enabled |\n");
            sb.Append("|-------------|----------------|------------|--------------|-----------------|\n");

            foreach (var a in admins.OrderBy(x => Str(x, "DisplayName") ?? "", StringComparer.OrdinalIgnoreCase))
            {
                string name = EscapePipe(Str(a, "DisplayName"));
                string registered = IsTrue(a, "MFARegistration") ? "✅ Yes" : "❌ No";
                string methods = EscapePipe(FormatMfaMethods(a));
                string protection = ProtectionVerbose(a);
                string enabled = IsTrue(a, "AccountEnabled") ? "Yes" : "Disabled";
                sb.Append($"| {name} | {registered} | {methods} | {protection} | {enabled} |\n");
            }

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
