using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.12.1 — Allowed senders list SHOULD NOT be used.
    /// Port of Invoke-CippTestCISAMSEXO121. Fails when the tenant allow/block list has any entry
    /// with <c>Action -eq 'Allow' -and ListType -eq 'Sender'</c>; renders the first 10.
    /// PS skip is <c>$null -eq $AllowBlockList</c>; with zero rows New-CIPPDbRequest returns $null,
    /// so the empty-array check reproduces it.
    /// </summary>
    public sealed class CISAMSEXO121 : ICippTest
    {
        public string Id => "CISAMSEXO121";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var list = data.Get("ExoTenantAllowBlockList");
            if (!Any(list))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoTenantAllowBlockList cache not found. Please refresh the cache for this tenant.");

            var allowed = new List<JsonElement>();
            foreach (var e in Items(list))
                if (StrEq(e, "Action", "Allow") && StrEq(e, "ListType", "Sender")) allowed.Add(e);

            if (allowed.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "✅ **Pass**: No allowed senders configured in tenant allow/block list.");

            var sb = new StringBuilder();
            sb.Append($"❌ **Fail**: {allowed.Count} allowed sender(s) configured in tenant allow/block list");
            if (allowed.Count > 10) sb.Append(" (showing first 10)");
            sb.Append(":\n\n");
            sb.Append("| Value | Action | List Type |\n");
            sb.Append("| :---- | :----- | :-------- |\n");
            int shown = 0;
            foreach (var e in allowed)
            {
                if (shown++ >= 10) break;
                sb.Append($"| {Cell(e, "Value")} | {Cell(e, "Action")} | {Cell(e, "ListType")} |\n");
            }
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
