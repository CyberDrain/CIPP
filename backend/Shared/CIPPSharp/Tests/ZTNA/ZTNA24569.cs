using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// FileVault encryption protects data on macOS devices.
    /// Port of Invoke-CippTestZTNA24569. IntuneDeviceConfigurations of type
    /// macOSEndpointProtectionConfiguration with fileVaultEnabled == true; Passed if any assigned.
    /// </summary>
    public sealed class ZTNA24569 : ICippTest
    {
        public string Id => "ZTNA24569";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var configs = data.Get("IntuneDeviceConfigurations");
            if (!Any(configs))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var fileVaultEnabled = new List<JsonElement>();
            foreach (var c in Items(configs))
                if (StrEq(c, "@odata.type", "#microsoft.graph.macOSEndpointProtectionConfiguration") && IsTrue(c, "fileVaultEnabled"))
                    fileVaultEnabled.Add(c);

            bool passed = fileVaultEnabled.FindAll(IsAssigned).Count > 0;

            var sb = new StringBuilder(passed
                ? "✅ macOS FileVault encryption policies are configured and assigned in Intune.\n\n"
                : "❌ No relevant macOS FileVault encryption policies are configured or assigned.\n\n");

            if (fileVaultEnabled.Count > 0)
            {
                sb.Append("## macOS FileVault Policies\n\n");
                sb.Append("| Policy Name | FileVault Enabled | Assigned |\n");
                sb.Append("| :---------- | :---------------- | :------- |\n");
                foreach (var p in fileVaultEnabled)
                {
                    var fv = IsTrue(p, "fileVaultEnabled") ? "✅ Yes" : "❌ No";
                    sb.Append($"| {Text(p, "displayName")} | {fv} | {(IsAssigned(p) ? "✅ Yes" : "❌ No")} |\n");
                }
            }
            else
            {
                sb.Append("No macOS Endpoint Protection policies with FileVault settings found.\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
