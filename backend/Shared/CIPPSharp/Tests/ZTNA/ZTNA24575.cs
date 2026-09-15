using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Defender Antivirus policies protect Windows devices from malware.
    /// Port of Invoke-CippTestZTNA24575. IntuneConfigurationPolicies (windows10/mdm/microsoftSense)
    /// with the endpointSecurityAntivirus template, and assigned.
    /// </summary>
    public sealed class ZTNA24575 : ICippTest
    {
        public string Id => "ZTNA24575";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("IntuneConfigurationPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var sense = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (PropContains(p, "platforms", "windows10") && PropContains(p, "technologies", "mdm")
                    && PropContains(p, "technologies", "microsoftSense"))
                    sense.Add(p);

            if (sense.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Windows Defender policies found");

            var av = new List<JsonElement>();
            foreach (var p in sense)
                if (string.Equals(NestedStr(p, "templateReference", "templateFamily"), "endpointSecurityAntivirus", System.StringComparison.OrdinalIgnoreCase))
                    av.Add(p);

            if (av.Count == 0)
                return new CippTestResult(TestStatus.Failed, "No Windows Defender Antivirus policies found");

            int assigned = av.FindAll(IsAssigned).Count;

            if (assigned > 0)
                return new CippTestResult(TestStatus.Passed,
                    $"Windows Defender Antivirus policies are configured and assigned. Found {assigned} assigned policy/policies");

            return new CippTestResult(TestStatus.Failed,
                $"Windows Defender Antivirus policies exist but are not assigned. Found {av.Count} unassigned policy/policies");
        }
    }
}
