using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Users have strong authentication methods configured.
    /// Port of Invoke-CippTestZTNA21801. Joins UserRegistrationDetails to enabled Users (by id);
    /// each joined user must have a phishing-resistant method registered. Passed only when all do.
    /// </summary>
    public sealed class ZTNA21801 : ICippTest
    {
        private static readonly string[] PhishResistantMethods =
            { "passKeyDeviceBound", "passKeyDeviceBoundAuthenticator", "windowsHelloForBusiness" };

        private const string UserLinkFormat =
            "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/UserAuthMethods/userId/{0}/hidePreviewBanner~/true";

        private const int MaxUsersToDisplay = 500;

        public string Id => "ZTNA21801";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var userReg = data.Get("UserRegistrationDetails");
            var users = data.Get("Users");

            if (!Any(userReg) || !Any(users))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            // Enabled-user lookup keyed by id.
            var enabledUsers = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var u in Items(users))
            {
                if (!IsTrue(u, "accountEnabled")) continue;
                var uid = Str(u, "id");
                if (uid != null) enabledUsers[uid] = u;
            }

            var phishable = new List<(string Display, string LastSignIn, string Id)>();
            var phishResistantWithId = new List<(string Display, string LastSignIn, string Id)>();

            foreach (var reg in Items(userReg))
            {
                var id = Str(reg, "id");
                if (id == null || !enabledUsers.TryGetValue(id, out var user)) continue;

                bool hasPhish = false;
                foreach (var m in PhishResistantMethods)
                    if (ArrContains(reg, "methodsRegistered", m)) { hasPhish = true; break; }

                var display = Str(reg, "userDisplayName") ?? "";
                var lastSignIn = CippTestHelpers.SignInDate(NestedStr(user, "signInActivity", "lastSuccessfulSignInDateTime"));
                if (hasPhish) phishResistantWithId.Add((display, lastSignIn, id));
                else phishable.Add((display, lastSignIn, id));
            }

            int total = phishable.Count + phishResistantWithId.Count;
            int phishResistantCount = phishResistantWithId.Count;
            bool passed = total == phishResistantCount;

            var header = passed
                ? "Validated that all users have registered phishing resistant authentication methods.\n\n"
                : "Found users that have not yet registered phishing resistant authentication methods\n\n";

            var md = new StringBuilder(passed
                ? "All users have registered phishing resistant authentication methods.\n\n"
                : "Found users that have not registered phishing resistant authentication methods.\n\n");
            md.Append("| User | Last sign in | Phishing resistant method registered |\n");
            md.Append("| :--- | :--- | :---: |\n");

            var phishableShown = phishable.OrderBy(x => x.Display, StringComparer.Ordinal).Take(MaxUsersToDisplay).ToList();
            foreach (var e in phishableShown)
                md.Append($"|[{e.Display}]({string.Format(UserLinkFormat, e.Id)})| {e.LastSignIn} | ❌ |\n");
            if (phishable.Count > MaxUsersToDisplay)
                md.Append($"|... and {phishable.Count - MaxUsersToDisplay} more users without phish-resistant methods|||\n");

            int remainingSlots = MaxUsersToDisplay - Math.Min(phishable.Count, MaxUsersToDisplay);
            if (remainingSlots > 0)
            {
                var resistantShown = phishResistantWithId.OrderBy(x => x.Display, StringComparer.Ordinal).Take(remainingSlots).ToList();
                foreach (var e in resistantShown)
                    md.Append($"|[{e.Display}]({string.Format(UserLinkFormat, e.Id)})| {e.LastSignIn} | ✅ |\n");
                if (phishResistantWithId.Count > remainingSlots)
                    md.Append($"|... and {phishResistantWithId.Count - remainingSlots} more users with phish-resistant methods|||\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, header + md.ToString());
        }
    }
}
