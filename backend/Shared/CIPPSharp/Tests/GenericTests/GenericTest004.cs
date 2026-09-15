using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Tenant MFA Report — full MFA posture overview for all accounts.
    /// Port of Invoke-CippTestGenericTest004. Single source: MFAState. Always Informational
    /// (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest004 : ICippTest
    {
        public string Id => "GenericTest004";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mfaData = data.Get("MFAState");
            if (!Any(mfaData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No MFA state data found in the reporting database. Please sync the MFA State cache first.");
            }

            var users = mfaData.EnumerateArray().Where(u => HasText(u, "UPN")).ToList();
            if (users.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "MFA state data was found but contained no user records.");
            }

            int total = users.Count;
            int mfaRegistered = 0, mfaCapable = 0, coveredByCA = 0, coveredBySD = 0, perUserMfa = 0, notProtected = 0, adminCount = 0;
            foreach (var u in users)
            {
                if (IsTrue(u, "MFARegistration")) mfaRegistered++;
                if (IsTrue(u, "MFACapable")) mfaCapable++;
                bool isCA = StartsWithCI(u, "CoveredByCA", "Enforced");
                bool isSD = IsTrue(u, "CoveredBySD");
                bool isPerUser = InList(u, "PerUser", "Enforced", "Enabled");
                if (isCA) coveredByCA++;
                if (isSD) coveredBySD++;
                if (isPerUser) perUserMfa++;
                if (!isCA && !isSD && !isPerUser) notProtected++;
                if (IsTrue(u, "IsAdmin")) adminCount++;
            }
            double mfaRegPct = total > 0 ? Round1((double)mfaRegistered / total * 100) : 0;

            var sb = new StringBuilder();
            sb.Append("### Summary\n\n");
            sb.Append("| Metric | Count |\n");
            sb.Append("|--------|-------|\n");
            sb.Append($"| Total Accounts | {total} |\n");
            sb.Append($"| Admin Accounts | {adminCount} |\n");
            sb.Append($"| Registered for MFA | {mfaRegistered} ({Fmt(mfaRegPct)}%) |\n");
            sb.Append($"| MFA Capable | {mfaCapable} |\n");
            sb.Append($"| Protected by Conditional Access | {coveredByCA} |\n");
            sb.Append($"| Protected by Security Defaults | {coveredBySD} |\n");
            sb.Append($"| Using Per-User MFA (Legacy) | {perUserMfa} |\n");
            sb.Append($"| **Not Protected by Any MFA Policy** | **{notProtected}** |\n\n");

            if (notProtected > 0)
                sb.Append($"**⚠️ {notProtected} account(s) have no MFA enforcement.** These accounts are at significantly higher risk of compromise. Consider enabling Conditional Access policies to require MFA for all users.\n\n");

            sb.Append("### All Accounts\n\n");
            sb.Append("| Display Name | MFA Registered | MFA Method | Protected By | Account Type |\n");
            sb.Append("|-------------|----------------|------------|--------------|--------------|\n");

            foreach (var u in users.OrderBy(x => Str(x, "DisplayName") ?? "", StringComparer.OrdinalIgnoreCase).Take(100))
            {
                string name = EscapePipe(Str(u, "DisplayName"));
                string registered = IsTrue(u, "MFARegistration") ? "✅ Yes" : "❌ No";
                string methods = EscapePipe(FormatMfaMethods(u));
                string protection = ProtectionVerbose(u);
                string acctType = IsTrue(u, "IsAdmin") ? "🔑 Admin" : "User";
                sb.Append($"| {name} | {registered} | {methods} | {protection} | {acctType} |\n");
            }

            if (users.Count > 100)
                sb.Append($"\n*Showing 100 of {users.Count} accounts.*\n");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
