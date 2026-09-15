using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guest self-service sign-up via user flow is disabled.
    /// Port of Invoke-CippTestZTNA21823. AuthenticationFlowsPolicy.selfServiceSignUp.isEnabled must
    /// be exactly false.
    /// </summary>
    public sealed class ZTNA21823 : ICippTest
    {
        private const string PortalLink =
            "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/~/Settings/menuId/ExternalIdentitiesGettingStarted";

        public string Id => "ZTNA21823";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policy = data.Get("AuthenticationFlowsPolicy");
            if (!Any(policy))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            bool disabled = false;
            foreach (var rec in Items(policy))
            {
                var isEnabled = Nested(rec, "selfServiceSignUp", "isEnabled");
                disabled = isEnabled.ValueKind == JsonValueKind.False;
                break; // singleton
            }

            if (disabled)
                return new CippTestResult(TestStatus.Passed,
                    $"[Guest self-service sign up via user flow]({PortalLink}) is disabled.\n");

            return new CippTestResult(TestStatus.Failed,
                $"[Guest self-service sign up via user flow]({PortalLink}) is enabled.\n");
        }
    }
}
