using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.1) — Microsoft Authenticator SHALL be configured to protect against MFA
    /// fatigue. Port of Invoke-CippTestCIS_5_2_3_1. Reads the authentication methods policy singleton
    /// and grades the MicrosoftAuthenticator method's app-context + geographic-location feature settings.
    /// </summary>
    public sealed class CIS_5_2_3_1 : ICippTest
    {
        public string Id => "CIS_5_2_3_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var amp = data.Get("AuthenticationMethodsPolicy");
            if (!Any(amp))
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");

            var cfg = FirstOrNull(amp)!.Value;
            var auth = FindInArray(Path(cfg, "authenticationMethodConfigurations"), "id", "MicrosoftAuthenticator");

            if (auth == null)
                return new CippTestResult(TestStatus.Failed,
                    "MicrosoftAuthenticator authentication method configuration not found.");

            var a = auth.Value;
            var incEl = Path(a, "featureSettings", "displayAppInformationRequiredState", "includeTarget", "id");
            var geoEl = Path(a, "featureSettings", "displayLocationInformationRequiredState", "includeTarget", "id");
            var inc = LeafStr(incEl);
            var geo = LeafStr(geoEl);

            if (StrEq(a, "state", "enabled")
                && LeafEqCI(Path(a, "featureSettings", "displayAppInformationRequiredState", "state"), "enabled")
                && LeafEqCI(Path(a, "featureSettings", "displayLocationInformationRequiredState", "state"), "enabled")
                && LeafEqCI(incEl, "all_users")
                && LeafEqCI(geoEl, "all_users"))
            {
                return new CippTestResult(TestStatus.Passed,
                    "Microsoft Authenticator has app context + geographic location enabled for all users.");
            }

            var appState = LeafStr(Path(a, "featureSettings", "displayAppInformationRequiredState", "state"));
            var locState = LeafStr(Path(a, "featureSettings", "displayLocationInformationRequiredState", "state"));
            var result =
                "Microsoft Authenticator is not fully hardened.\n\n"
                + $"- state: {LeafStr(Path(a, "state"))}\n"
                + $"- displayAppInformation: {appState} (target: {inc})\n"
                + $"- displayLocation: {locState} (target: {geo})";
            return new CippTestResult(TestStatus.Failed, result);
        }
    }
}
