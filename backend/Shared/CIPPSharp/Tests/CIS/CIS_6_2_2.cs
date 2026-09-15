using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (6.2.2) — Mail transport rules SHALL NOT whitelist specific domains.
    /// Port of Invoke-CippTestCIS_6_2_2. Flags enabled transport rules that whitelist senders by
    /// setting SCL to -1, adding an IPV:CAL Antispam header, or bypassing Clutter.
    /// </summary>
    public sealed class CIS_6_2_2 : ICippTest
    {
        public string Id => "CIS_6_2_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var rules = data.Get("ExoTransportRules");
            if (!Any(rules))
                return new CippTestResult(TestStatus.Skipped, "ExoTransportRules cache not found.");

            var whitelisting = new List<JsonElement>();
            foreach (var r in rules.EnumerateArray())
            {
                if (StrEq(r, "State", "Enabled")
                    && (IntEq(r, "SetSCL", -1)
                        || (StrEq(r, "SetHeaderName", "X-Forefront-Antispam-Report")
                            && MatchCI(Str(r, "SetHeaderValue"), "IPV:CAL"))
                        || StrEq(r, "SetHeaderName", "X-MS-Exchange-Organization-BypassClutter")
                        || IntEq(r, "SetSpamConfidenceLevel", -1)))
                {
                    whitelisting.Add(r);
                }
            }

            if (whitelisting.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No enabled transport rule whitelists senders by setting SCL to -1.");

            var sb = new StringBuilder();
            sb.Append($"{whitelisting.Count} transport rule(s) whitelist senders by SCL=-1:\n\n");
            var lines = new List<string>();
            int shown = 0;
            foreach (var w in whitelisting)
            {
                if (shown++ >= 25) break;
                lines.Add($"- {Str(w, "Name")}");
            }
            sb.Append(string.Join("\n", lines));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
