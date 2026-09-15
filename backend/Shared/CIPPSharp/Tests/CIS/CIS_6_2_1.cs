using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (6.2.1) — All forms of mail forwarding SHALL be blocked and/or disabled.
    /// Port of Invoke-CippTestCIS_6_2_1. Auto-forwarding must be Off on the (default) outbound spam
    /// filter policy AND disabled on the Default remote domain.
    /// </summary>
    public sealed class CIS_6_2_1 : ICippTest
    {
        public string Id => "CIS_6_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var outbound = data.Get("ExoHostedOutboundSpamFilterPolicy");
            var remote = data.Get("ExoRemoteDomain");

            if (!Any(outbound))
                return new CippTestResult(TestStatus.Skipped, "ExoHostedOutboundSpamFilterPolicy cache not found.");

            JsonElement? def = null;
            foreach (var o in outbound.EnumerateArray())
                if (BoolEq(o, "IsDefault", true)) { def = o; break; }
            if (def == null) def = FirstOrNull(outbound);
            var d = def!.Value;

            var autoForwardOff = StrEq(d, "AutoForwardingMode", "Off");

            var remoteDefault = FindInArray(remote, "Name", "Default");
            var remoteForwardOff = remoteDefault == null || BoolEq(remoteDefault.Value, "AutoForwardEnabled", false);

            if (autoForwardOff && remoteForwardOff)
                return new CippTestResult(TestStatus.Passed,
                    "Auto-forwarding is blocked at the outbound spam filter (AutoForwardingMode: Off) and disabled on the default remote domain.");

            var remoteVal = remoteDefault == null ? "" : (Str(remoteDefault.Value, "AutoForwardEnabled") ?? "");
            return new CippTestResult(TestStatus.Failed,
                "Auto-forwarding is not fully blocked.\n\n"
                + $"- Outbound spam filter AutoForwardingMode: {Str(d, "AutoForwardingMode")}\n"
                + $"- Default remote domain AutoForwardEnabled: {remoteVal}");
        }
    }
}
