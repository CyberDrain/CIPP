using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// MS.EXO.11.1 — Impersonation protection checks SHOULD be used.
    /// Port of Invoke-CippTestCISAMSEXO111. Passes when at least one of: an enabled Standard EOP
    /// preset, an enabled Strict EOP preset, or any preset with impersonation protection enabled.
    /// </summary>
    public sealed class CISAMSEXO111 : ICippTest
    {
        public string Id => "CISAMSEXO111";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoPresetSecurityPolicy");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.");

            bool standardEop = false, strictEop = false;
            int atpCount = 0;
            foreach (var p in Items(policies))
            {
                if (StrEq(p, "Identity", "Standard Preset Security Policy") && StrEq(p, "State", "Enabled")) standardEop = true;
                if (StrEq(p, "Identity", "Strict Preset Security Policy") && StrEq(p, "State", "Enabled")) strictEop = true;

                var identity = Str(p, "Identity");
                if (identity != null
                    && identity.IndexOf("Preset Security Policy", StringComparison.OrdinalIgnoreCase) >= 0
                    && StrEq(p, "ImpersonationProtectionState", "Enabled"))
                    atpCount++;
            }

            var enabled = new List<string>();
            if (standardEop) enabled.Add("Standard EOP");
            if (strictEop) enabled.Add("Strict EOP");
            if (atpCount > 0) enabled.Add($"{atpCount} ATP policy/policies with impersonation protection");

            if (enabled.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append("✅ **Pass**: Preset security policies with impersonation protection are enabled:\n\n");
                sb.Append(string.Join("\n", enabled.ConvertAll(e => "- " + e)));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "❌ **Fail**: No preset security policies with impersonation protection enabled.\n\n"
                + "Enable Standard or Strict preset security policies to provide impersonation protection.");
        }
    }
}
