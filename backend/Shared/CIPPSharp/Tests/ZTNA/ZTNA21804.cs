using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMS and Voice Call authentication methods are disabled (Weak authentication methods are disabled).
    /// Port of Invoke-CippTestZTNA21804. Fails if any Sms/Voice method config has state 'enabled'.
    /// </summary>
    public sealed class ZTNA21804 : ICippTest
    {
        public string Id => "ZTNA21804";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            if (!Any(authMethods))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matched = new List<JsonElement>();
            foreach (var rec in Items(authMethods))
                foreach (var m in Arr(rec, "authenticationMethodConfigurations"))
                    if (StrEq(m, "id", "Sms") || StrEq(m, "id", "Voice")) matched.Add(m);

            bool anyEnabled = false;
            foreach (var m in matched) if (StrEq(m, "state", "enabled")) { anyEnabled = true; break; }

            var text = anyEnabled
                ? "Found weak authentication methods that are still enabled."
                : "SMS and voice calls authentication methods are disabled in the tenant.";

            var sb = new StringBuilder(text);
            sb.Append("\n## Weak authentication methods\n\n");
            sb.Append("| Method ID | Is method weak? | State |\n");
            sb.Append("| :-------- | :-------------- | :---- |\n");
            foreach (var m in matched)
                sb.Append($"| {Text(m, "id")} | Yes | {Text(m, "state")} |\n");

            return new CippTestResult(anyEnabled ? TestStatus.Failed : TestStatus.Passed, sb.ToString());
        }
    }
}
