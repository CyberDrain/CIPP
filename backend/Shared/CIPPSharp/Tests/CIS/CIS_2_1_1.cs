using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.1) — Safe Links for Office Applications SHALL be enabled.
    /// Port of Invoke-CippTestCIS_2_1_1. A policy is compliant only when all nine Safe Links
    /// settings match the CIS baseline.
    ///
    /// NOTE (parity limitation): the PS test distinguishes "collected but no policy" (→ Failed,
    /// via a Get-CIPPDbItem -CountsOnly marker) from "never collected" (→ Skipped). The count
    /// marker row carries no Data payload, so TenantData cannot see it; both cases arrive here as
    /// an empty array. This port takes the conservative Skipped branch on empty data.
    /// </summary>
    public sealed class CIS_2_1_1 : ICippTest
    {
        public string Id => "CIS_2_1_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoSafeLinksPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoSafeLinksPolicies has not been collected for this tenant. Run a Cache refresh (Cache & Tests); if it persists, the tenant may not have Defender for Office 365.");
            }

            var compliant = new List<JsonElement>();
            foreach (var p in policies.EnumerateArray())
            {
                if (IsTrue(p, "EnableSafeLinksForEmail")
                    && IsTrue(p, "EnableSafeLinksForTeams")
                    && IsTrue(p, "EnableSafeLinksForOffice")
                    && IsTrue(p, "TrackClicks")
                    && IsFalse(p, "AllowClickThrough")
                    && IsTrue(p, "ScanUrls")
                    && IsTrue(p, "EnableForInternalSenders")
                    && IsTrue(p, "DeliverMessageAfterScan")
                    && IsFalse(p, "DisableUrlRewrite"))
                {
                    compliant.Add(p);
                }
            }

            if (compliant.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{compliant.Count} Safe Links policy/policies meet all CIS requirements:\n\n");
                var lines = new List<string>();
                foreach (var p in compliant) lines.Add($"- {Str(p, "Name")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append("No Safe Links policy meets every CIS requirement (Email/Teams/Office on, ScanUrls/TrackClicks on, AllowClickThrough off, DisableUrlRewrite off, DeliverMessageAfterScan on, EnableForInternalSenders on).");
            f.Append("\n\n**Existing policies:**\n");
            var elines = new List<string>();
            foreach (var p in policies.EnumerateArray())
            {
                elines.Add($"- {Str(p, "Name")}: SafeLinksForEmail={Cell(Prop(p, "EnableSafeLinksForEmail"))}, Office={Cell(Prop(p, "EnableSafeLinksForOffice"))}, Teams={Cell(Prop(p, "EnableSafeLinksForTeams"))}");
            }
            f.Append(string.Join("\n", elines));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
