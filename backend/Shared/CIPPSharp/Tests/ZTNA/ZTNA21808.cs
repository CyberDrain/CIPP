using System;
using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Restrict device code flow.
    /// Port of Invoke-CippTestZTNA21808. Among enabled CA policies, those whose
    /// authenticationFlows.transferMethods (comma-delimited) include deviceCodeFlow must include a
    /// block control.
    /// </summary>
    public sealed class ZTNA21808 : ICippTest
    {
        public string Id => "ZTNA21808";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var deviceCode = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                if (!StrEq(p, "state", "enabled")) continue;
                var transfer = NestedStr(p, "conditions", "authenticationFlows", "transferMethods");
                if (string.IsNullOrEmpty(transfer)) continue;
                bool hasDeviceCode = false;
                foreach (var method in transfer!.Split(','))
                    if (string.Equals(method, "deviceCodeFlow", StringComparison.OrdinalIgnoreCase)) { hasDeviceCode = true; break; }
                if (hasDeviceCode) deviceCode.Add(p);
            }

            int blockCount = 0;
            foreach (var p in deviceCode)
                if (FlattenContains(p, "block", "grantControls", "builtInControls")) blockCount++;

            if (blockCount > 0)
                return new CippTestResult(TestStatus.Passed,
                    $"Device code flow is properly restricted with {blockCount} blocking policy/policies");

            if (deviceCode.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "No Conditional Access policies found targeting device code flow");

            return new CippTestResult(TestStatus.Failed,
                "Device code flow policies exist but none are configured to block");
        }
    }
}
