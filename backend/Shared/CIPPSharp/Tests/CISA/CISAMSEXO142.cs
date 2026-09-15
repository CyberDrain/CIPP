using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.14.2 — Spam SHALL be moved to junk email or quarantine.
    /// Port of Invoke-CippTestCISAMSEXO142. Fails policies whose <c>SpamAction</c> is
    /// <c>-notin ('MoveToJmf','Quarantine')</c> (missing action counts as failing).
    /// </summary>
    public sealed class CISAMSEXO142 : ICippTest
    {
        public string Id => "CISAMSEXO142";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoHostedContentFilterPolicy");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.");

            var failed = new List<JsonElement>();
            int total = 0;
            foreach (var p in Items(policies))
            {
                total++;
                if (!In(p, "SpamAction", "MoveToJmf", "Quarantine")) failed.Add(p);
            }

            if (failed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"✅ **Pass**: All {total} anti-spam policy/policies move spam to junk folder or quarantine.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {failed.Count} of {total} anti-spam policy/policies do not properly handle spam:\n\n");
            sb.Append("| Policy Name | Current Action | Expected |\n");
            sb.Append("| :---------- | :------------- | :------- |\n");
            foreach (var p in failed)
                sb.Append($"| {Cell(p, "Name")} | {Cell(p, "SpamAction")} | MoveToJmf or Quarantine |\n");
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
