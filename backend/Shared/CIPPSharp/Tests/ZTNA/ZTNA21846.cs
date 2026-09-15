using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Restrict Temporary Access Pass to Single Use.
    /// Port of Invoke-CippTestZTNA21846. TAP config isUsableOnce must be true.
    /// </summary>
    public sealed class ZTNA21846 : ICippTest
    {
        public string Id => "ZTNA21846";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");

            JsonElement tap = default;
            bool tapFound = false;
            foreach (var rec in Items(authMethods))
                foreach (var m in Arr(rec, "authenticationMethodConfigurations"))
                    if (StrEq(m, "id", "TemporaryAccessPass")) { tap = m; tapFound = true; break; }

            if (!tapFound)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            bool usableOnce = IsTrue(tap, "isUsableOnce");

            var sb = new StringBuilder(usableOnce
                ? "Temporary Access Pass is configured for one-time use only.\n\n"
                : "Temporary Access Pass allows multiple uses during validity period.\n\n");
            sb.Append("## Temporary Access Pass Configuration\n\n");
            sb.Append("| Setting | Value | Status |\n");
            sb.Append("| :------ | :---- | :----- |\n");
            string value = usableOnce ? "Enabled" : "Disabled";
            string statusEmoji = usableOnce ? "✅ Pass" : "❌ Fail";
            sb.Append($"| [One-time use restriction](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods/fromNav/) | {value} | {statusEmoji} |\n");

            return new CippTestResult(usableOnce ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
