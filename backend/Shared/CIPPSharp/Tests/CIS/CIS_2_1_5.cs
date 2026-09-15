using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.5) — Safe Attachments for SharePoint, OneDrive, and Teams SHALL be enabled.
    /// Port of Invoke-CippTestCIS_2_1_5. Requires the ATP-for-O365 policy to enable ATP for
    /// SPO/Teams/ODB and Safe Docs, with AllowSafeDocsOpen off.
    ///
    /// NOTE (parity limitation): the PS "collected but no policy" (→ Failed) vs "never collected"
    /// (→ Skipped) split relies on a count marker TenantData cannot see; this port takes the
    /// Skipped branch on empty data.
    /// </summary>
    public sealed class CIS_2_1_5 : ICippTest
    {
        // Preserves the PS $Required order (hashtable enumeration order is not guaranteed in PS,
        // but the verdict does not depend on it).
        private static readonly (string Key, bool Expected)[] Required =
        {
            ("EnableATPForSPOTeamsODB", true),
            ("EnableSafeDocs", true),
            ("AllowSafeDocsOpen", false),
        };

        public string Id => "CIS_2_1_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var atp = data.Get("ExoAtpPolicyForO365");
            if (!Any(atp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoAtpPolicyForO365 has not been collected for this tenant. Run a Cache refresh (Cache & Tests); if it persists, the tenant may not have Defender for Office 365.");
            }

            var cfg = FirstOrNull(atp)!.Value;
            var failures = new List<string>();
            foreach (var (key, expected) in Required)
            {
                if (!BoolEq(cfg, key, expected))
                    failures.Add($"{key} = {Cell(Prop(cfg, key))} (expected {BoolStr(expected)})");
            }

            if (failures.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "Safe Attachments for SharePoint, OneDrive and Teams is fully enabled.");
            }

            var sb = new StringBuilder();
            sb.Append("Configuration mismatch on ATP policy:\n\n");
            var lines = new List<string>();
            foreach (var f in failures) lines.Add($"- {f}");
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
