using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.15) — Outbound anti-spam message limits SHALL be in place.
    /// Port of Invoke-CippTestCIS_2_1_15. Inspects the default (or first) outbound spam policy.
    /// </summary>
    public sealed class CIS_2_1_15 : ICippTest
    {
        public string Id => "CIS_2_1_15";

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

            long external = Int(d, "RecipientLimitExternalPerHour");
            long internalLimit = Int(d, "RecipientLimitInternalPerHour");
            long daily = Int(d, "RecipientLimitPerDay");
            var action = Str(d, "ActionWhenThresholdReached");

            bool pass = external > 0 && external <= 500
                && internalLimit > 0 && internalLimit <= 1000
                && daily > 0 && daily <= 1000
                && InListCI(action, "BlockUser", "BlockUserForToday");

            var identity = Str(d, "Identity");
            if (pass)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Outbound anti-spam limits are within CIS recommendations on '{identity}'.\n\n- External/hr: {external}\n- Internal/hr: {internalLimit}\n- Daily: {daily}\n- Action: {action}");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Outbound limits on '{identity}' do not meet CIS recommended values (External<=500/hr, Internal<=1000/hr, Daily<=1000, Action=BlockUser):\n\n- External/hr: {external}\n- Internal/hr: {internalLimit}\n- Daily: {daily}\n- Action: {action}");
        }
    }
}
