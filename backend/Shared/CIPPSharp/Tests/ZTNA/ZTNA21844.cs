using System;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Block legacy Azure AD PowerShell module.
    /// Port of Invoke-CippTestZTNA21844. Passed when the Azure AD PowerShell service principal has sign
    /// in disabled; Skipped when app role assignment is required (the PS 'InvestigateStatus' path
    /// emits Status 'Skipped'); Failed otherwise (including when the SP is absent).
    /// </summary>
    public sealed class ZTNA21844 : ICippTest
    {
        private const string AzureADPowerShellAppId = "1b730954-1685-4b74-9bfd-dac224a7b894";
        private const string AppName = "Azure AD PowerShell";

        public string Id => "ZTNA21844";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            JsonElement sp = default;
            bool found = false;
            foreach (var s in Items(data.Get("ServicePrincipals")))
                if (StrEq(s, "appId", AzureADPowerShellAppId)) { sp = s; found = true; break; }

            bool investigate = false;
            bool passed = false; // 'Failed' default
            string summary;

            if (!found)
            {
                summary = string.Join("\n", new[]
                {
                    "Summary", "",
                    $"- {AppName} (Enterprise App not found in tenant)",
                    "- Sign in disabled: N/A", "",
                    $"{AppName} has not been blocked by the organization."
                });
            }
            else
            {
                var portalLink = $"https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/{Str(sp, "id")}/appId/{Str(sp, "appId")}";
                var spLink = $"[{AppName}]({portalLink})";
                var accountEnabled = Prop(sp, "accountEnabled");
                bool accountDisabled = accountEnabled.ValueKind == JsonValueKind.False
                    || (accountEnabled.ValueKind == JsonValueKind.String && string.Equals(accountEnabled.GetString(), "false", StringComparison.OrdinalIgnoreCase));

                if (accountDisabled)
                {
                    passed = true;
                    summary = string.Join("\n", new[]
                    {
                        "Summary", "", $"- {spLink}", "- Sign in disabled: Yes", "",
                        $"{AppName} is blocked in the tenant by turning off user sign in to the Azure Active Directory PowerShell Enterprise Application."
                    });
                }
                else if (IsTrue(sp, "appRoleAssignmentRequired"))
                {
                    investigate = true;
                    summary = string.Join("\n", new[]
                    {
                        "Summary", "", $"- {spLink}", "- Sign in disabled: No", "- User assignment required: Yes", "",
                        $"App role assignment is required for {AppName}. Review assignments and confirm that the app is inaccessible to users."
                    });
                }
                else
                {
                    summary = string.Join("\n", new[]
                    {
                        "Summary", "", $"- {spLink}", "- Sign in disabled: No", "",
                        $"{AppName} has not been blocked by the organization."
                    });
                }
            }

            if (investigate)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, summary);
        }
    }
}
