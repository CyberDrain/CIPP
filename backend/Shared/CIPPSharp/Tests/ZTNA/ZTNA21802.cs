using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Microsoft Authenticator app shows sign-in context.
    /// Port of Invoke-CippTestZTNA21802. The MicrosoftAuthenticator method config must enable both
    /// displayAppInformationRequiredState and displayLocationInformationRequiredState.
    /// </summary>
    public sealed class ZTNA21802 : ICippTest
    {
        public string Id => "ZTNA21802";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            JsonElement authenticator = default;
            bool found = false;
            foreach (var rec in Items(authMethods))
            {
                foreach (var m in Arr(rec, "authenticationMethodConfigurations"))
                {
                    if (StrEq(m, "id", "MicrosoftAuthenticator")) { authenticator = m; found = true; break; }
                }
                if (found) break;
            }

            if (!found)
                return new CippTestResult(TestStatus.Failed,
                    "Microsoft Authenticator configuration not found in authentication methods policy");

            var feature = Prop(authenticator, "featureSettings");
            bool appInfo = string.Equals(NestedStr(feature, "displayAppInformationRequiredState", "state"), "enabled", System.StringComparison.OrdinalIgnoreCase);
            bool locationInfo = string.Equals(NestedStr(feature, "displayLocationInformationRequiredState", "state"), "enabled", System.StringComparison.OrdinalIgnoreCase);

            if (appInfo && locationInfo)
                return new CippTestResult(TestStatus.Passed,
                    "Microsoft Authenticator shows application name and geographic location in push notifications");

            return new CippTestResult(TestStatus.Failed,
                $"Microsoft Authenticator sign-in context incomplete - App info: {(appInfo ? "True" : "False")}, Location info: {(locationInfo ? "True" : "False")}");
        }
    }
}
