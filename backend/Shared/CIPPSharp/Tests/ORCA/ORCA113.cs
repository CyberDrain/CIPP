using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// AllowClickThrough is disabled in Safe Links policies. Port of Invoke-CippTestORCA113.
    /// Single source: ExoSafeLinksPolicies (excluding the Built-In Protection preset). Licensing is
    /// gated upstream by the engine. A custom policy passes when AllowClickThrough = false.
    /// </summary>
    public sealed class ORCA113 : ICippTest
    {
        public string Id => "ORCA113";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoSafeLinksPolicies"))
                return new CippTestResult(TestStatus.Skipped, DefenderNoDataMarkdown);

            // Exclude the Built-In Protection preset (Microsoft owns it and allows click-through by design).
            var custom = Items(data.Get("ExoSafeLinksPolicies"))
                .Where(p => !IsTrue(p, "IsBuiltInProtection")).ToList();

            var passed = custom.Where(p => IsFalse(p, "AllowClickThrough")).ToList();
            var failed = custom.Where(p => !IsFalse(p, "AllowClickThrough")).ToList();

            if (passed.Count > 0 && failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All custom Safe Links policies have click-through disabled (AllowClickThrough = false).\n\n");
                sb.Append($"**Compliant Policies:** {passed.Count}\n\n");
                var rows = passed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "AllowClickThrough") }).ToList();
                sb.Append(Markdown.Table(new[] { "Policy Name", "AllowClickThrough" }, rows));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            if (passed.Count == 0 && failed.Count == 0)
            {
                return new CippTestResult(TestStatus.Failed,
                    "No custom Safe Links policies are configured. The Built-In Protection policy allows click-through by design.\n\n**Remediation:** Create a custom Safe Links policy with AllowClickThrough = $false.");
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} custom Safe Links policies allow click-through, which reduces protection.\n\n");
            f.Append($"**Failed Policies:** {failed.Count} | **Passed Policies:** {passed.Count}\n\n");
            f.Append("### Non-Compliant Policies\n\n");
            var frows = failed.Select(p => (IReadOnlyList<string>)new[] { CellOf(p, "Identity"), CellOf(p, "AllowClickThrough"), "false" }).ToList();
            f.Append(Markdown.Table(new[] { "Policy Name", "AllowClickThrough", "Recommended" }, frows));
            f.Append("\n**Remediation:** Set AllowClickThrough to false to prevent users from bypassing Safe Links protection.");
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
