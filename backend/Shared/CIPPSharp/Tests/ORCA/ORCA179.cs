using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Safe Links is enabled intra-organization (EnableForInternalSenders == true) for custom policies.
    /// Port of Invoke-CippTestORCA179. Single source: ExoSafeLinksPolicies. Licensing is gated upstream by the engine.
    /// The Built-In Protection preset (IsBuiltInProtection == true) is excluded — Microsoft scopes it to
    /// external senders by design.
    /// </summary>
    public sealed class ORCA179 : ICippTest
    {
        public string Id => "ORCA179";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoSafeLinksPolicies"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            // $_.IsBuiltInProtection -ne $true : missing/false kept, true excluded (EXO string-bool safe).
            var custom = Items(data.Get("ExoSafeLinksPolicies"))
                .Where(p => !IsTrue(p, "IsBuiltInProtection")).ToList();

            var passed = custom.Where(p => IsTrue(p, "EnableForInternalSenders")).ToList();
            var failed = custom.Where(p => !IsTrue(p, "EnableForInternalSenders")).ToList();

            if (passed.Count > 0 && failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All custom Safe Links policies are enabled for internal senders.\n\n");
                sb.Append($"**Compliant Policies:** {passed.Count}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            if (passed.Count == 0 && failed.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No custom Safe Links policies are configured. The Built-In Protection policy does not cover internal senders.\n\n**Remediation:** Create a custom Safe Links policy with EnableForInternalSenders = $true.");
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} Safe Links policies are not enabled for internal senders.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "EnableForInternalSenders") }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "Enable For Internal Senders" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
