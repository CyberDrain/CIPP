using System;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Microsoft Authenticator app report suspicious activity setting is enabled.
    /// Port of Invoke-CippTestZTNA21841. reportSuspiciousActivitySettings must be enabled and target
    /// all users.
    /// </summary>
    public sealed class ZTNA21841 : ICippTest
    {
        private const string PortalLink =
            "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AuthMethodsSettings";

        public string Id => "ZTNA21841";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement report = default;
            bool hasReport = false;
            foreach (var rec in Items(authMethods))
            {
                var r = Prop(rec, "reportSuspiciousActivitySettings");
                if (r.ValueKind != JsonValueKind.Undefined && r.ValueKind != JsonValueKind.Null) { report = r; hasReport = true; }
                break; // singleton
            }

            if (!hasReport)
                return new CippTestResult(TestStatus.Failed,
                    $"Authenticator app report suspicious activity is [not enabled]({PortalLink}).");

            bool stateEnabled = StrEq(report, "state", "enabled");
            bool targetAllUsers = false;
            var includeTarget = Prop(report, "includeTarget");
            if (includeTarget.ValueKind != JsonValueKind.Undefined && includeTarget.ValueKind != JsonValueKind.Null)
                targetAllUsers = string.Equals(Str(includeTarget, "id"), "all_users", StringComparison.OrdinalIgnoreCase);

            if (stateEnabled && targetAllUsers)
                return new CippTestResult(TestStatus.Passed,
                    $"Authenticator app report suspicious activity is [enabled for all users]({PortalLink}).");

            if (!stateEnabled)
                return new CippTestResult(TestStatus.Failed,
                    $"Authenticator app report suspicious activity is [not enabled]({PortalLink}).");

            // stateEnabled but not all users
            return new CippTestResult(TestStatus.Failed,
                $"Authenticator app report suspicious activity is [not configured for all users]({PortalLink}).");
        }
    }
}
