using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.6) — Exchange Online Spam Policies SHALL be set to notify administrators.
    /// Port of Invoke-CippTestCIS_2_1_6. Inspects the default (or first) outbound spam filter policy.
    /// </summary>
    public sealed class CIS_2_1_6 : ICippTest
    {
        public string Id => "CIS_2_1_6";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoHostedOutboundSpamFilterPolicy");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoHostedOutboundSpamFilterPolicy cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? def = null;
            foreach (var p in policies.EnumerateArray())
                if (IsTrue(p, "IsDefault")) { def = p; break; }
            if (def == null) def = FirstOrNull(policies);
            var d = def!.Value;

            bool compliant = IsTrue(d, "NotifyOutboundSpam")
                && IsTrue(d, "BccSuspiciousOutboundMail")
                && CountGt0(d, "NotifyOutboundSpamRecipients")
                && CountGt0(d, "BccSuspiciousOutboundAdditionalRecipients");

            if (compliant)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Outbound spam notifications are configured on '{Str(d, "Identity")}'. Notify recipients: {JoinArr(d, "NotifyOutboundSpamRecipients")}.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Outbound spam notifications are not fully configured on '{Str(d, "Identity")}':\n\n- NotifyOutboundSpam: {Cell(Prop(d, "NotifyOutboundSpam"))}\n- BccSuspiciousOutboundMail: {Cell(Prop(d, "BccSuspiciousOutboundMail"))}\n- NotifyOutboundSpamRecipients: {JoinArr(d, "NotifyOutboundSpamRecipients")}\n- BccSuspiciousOutboundAdditionalRecipients: {JoinArr(d, "BccSuspiciousOutboundAdditionalRecipients")}");
        }

        private static string JoinArr(JsonElement el, string name)
        {
            var parts = new List<string>();
            foreach (var v in Arr(el, name)) parts.Add(Cell(v));
            return string.Join(", ", parts);
        }
    }
}
