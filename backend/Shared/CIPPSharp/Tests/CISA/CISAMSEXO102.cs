using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.10.2 — Emails identified as malware SHALL be quarantined or dropped.
    /// Port of Invoke-CippTestCISAMSEXO102. Fails policies whose <c>FileTypeAction</c> is
    /// <c>-notin ('Quarantine','Reject')</c> (case-insensitive; missing action counts as failing).
    ///
    /// PARITY NOTE (deliberate divergence — see W3 report): <c>FileTypeAction</c> is a real
    /// Get-MalwareFilterPolicy property (values Reject/Quarantine) but it is NOT in the
    /// <c>ExoMalwareFilterPolicies</c> field manifest (Get-CippTestDataFieldManifest). The PS test
    /// therefore reads it projected-away as $null, so <c>$null -notin (...)</c> is true and the PS
    /// test fails EVERY policy on EVERY tenant — a silent manifest omission. This C# engine reads
    /// whole rows (no projection), sees the real value, and returns the correct verdict. Expect an
    /// EXO102 verdict diff vs PS at the parity check; the fix on the PS side is to add
    /// 'FileTypeAction' to the manifest.
    /// </summary>
    public sealed class CISAMSEXO102 : ICippTest
    {
        public string Id => "CISAMSEXO102";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoMalwareFilterPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.");

            var failed = new List<JsonElement>();
            int total = 0;
            foreach (var p in Items(policies))
            {
                total++;
                if (!In(p, "FileTypeAction", "Quarantine", "Reject")) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} malware filter policy/policies quarantine or delete emails with malware.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} malware filter policy/policies do not quarantine or delete malware:\n\n");
            sb.Append("| Policy Name | Current Action | Expected |\n");
            sb.Append("| :---------- | :------------- | :------- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "FileTypeAction")} | Quarantine or Reject |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
