using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Legacy Per-User MFA Report — accounts still using per-user MFA enforcement.
    /// Port of Invoke-CippTestGenericTest008. Single source: MFAState. Always Informational
    /// (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest008 : ICippTest
    {
        public string Id => "GenericTest008";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var mfaData = data.Get("MFAState");
            if (!Any(mfaData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No MFA state data found in the reporting database. Please sync the MFA State cache first.");
            }

            var perUserUsers = mfaData.EnumerateArray()
                .Where(u => HasText(u, "UPN") && InList(u, "PerUser", "Enforced", "Enabled"))
                .ToList();

            var sb = new StringBuilder();
            if (perUserUsers.Count == 0)
            {
                sb.Append("**✅ No accounts are using legacy Per-User MFA.** Your tenant is not relying on the deprecated per-user MFA enforcement method.\n\n");
                sb.Append("Make sure your accounts are protected by Conditional Access policies or Security Defaults instead.");
                return new CippTestResult(TestStatus.Informational, sb.ToString());
            }

            int enforcedCount = 0, enabledCount = 0, adminsAffected = 0;
            foreach (var u in perUserUsers)
            {
                if (StrEq(u, "PerUser", "Enforced")) enforcedCount++;
                if (StrEq(u, "PerUser", "Enabled")) enabledCount++;
                if (IsTrue(u, "IsAdmin")) adminsAffected++;
            }

            sb.Append("### Current Status\n\n");
            sb.Append($"**⚠️ {perUserUsers.Count} account(s) are still using legacy Per-User MFA.**\n\n");
            sb.Append("| Status | Count |\n");
            sb.Append("|--------|-------|\n");
            sb.Append($"| Per-User MFA Enforced | {enforcedCount} |\n");
            sb.Append($"| Per-User MFA Enabled | {enabledCount} |\n");
            if (adminsAffected > 0)
                sb.Append($"| Admin Accounts Affected | {adminsAffected} |\n");
            sb.Append("\n");

            sb.Append("### Accounts Using Per-User MFA\n\n");
            sb.Append("The following accounts should be migrated to Conditional Access policies:\n\n");
            sb.Append("| Display Name | Per-User MFA Status | Also Covered by CA | Account Type | Licensed |\n");
            sb.Append("|-------------|--------------------|--------------------|--------------|----------|\n");

            foreach (var u in perUserUsers.OrderBy(x => Str(x, "DisplayName") ?? "", StringComparer.OrdinalIgnoreCase))
            {
                string name = Str(u, "DisplayName") ?? "";
                string perUserStatus = Str(u, "PerUser") ?? "";
                string caProtected = StartsWithCI(u, "CoveredByCA", "Enforced") ? "✅ Yes" : "❌ No";
                string acctType = IsTrue(u, "IsAdmin") ? "🔑 Admin" : "User";
                string licensed = IsTrue(u, "isLicensed") ? "Yes" : "No";
                sb.Append($"| {name} | {perUserStatus} | {caProtected} | {acctType} | {licensed} |\n");
            }

            sb.Append("\n### Recommended Migration Steps\n\n");
            sb.Append("1. **Create a Conditional Access policy** that requires MFA for all users (or start with admins)\n");
            sb.Append("2. **Verify** the Conditional Access policy is working correctly for affected users\n");
            sb.Append("3. **Disable Per-User MFA** for each account listed above once confirmed\n");
            sb.Append("4. **Test sign-in** to confirm users can still authenticate properly\n");

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }
    }
}
