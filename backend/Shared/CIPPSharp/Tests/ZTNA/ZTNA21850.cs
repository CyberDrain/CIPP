using System.Globalization;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Smart lockout threshold set to 10 or less.
    /// Port of Invoke-CippTestZTNA21850. Reads the 'Password Rule Settings' record from the Settings
    /// cache. Missing template or missing LockoutThreshold value → Failed. Otherwise Passed when the
    /// configured threshold is &lt;= 10. Never Skipped.
    /// </summary>
    public sealed class ZTNA21850 : ICippTest
    {
        public string Id => "ZTNA21850";

        private const string PortalLink =
            "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/PasswordProtection/fromNav/";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");

            JsonElement rule = default;
            bool found = false;
            foreach (var s in Items(settings))
                if (StrEq(s, "displayName", "Password Rule Settings")) { rule = s; found = true; break; }

            if (!found)
                return new CippTestResult(TestStatus.Failed, "❌ Password rule settings template not found.");

            JsonElement setting = default;
            bool haveSetting = false;
            foreach (var v in Arr(rule, "values"))
                if (StrEq(v, "name", "LockoutThreshold")) { setting = v; haveSetting = true; break; }

            if (!haveSetting)
                return new CippTestResult(TestStatus.Failed,
                    $"❌ Lockout threshold setting not found in [password rule settings]({PortalLink}).");

            long threshold = ParseInt(Str(setting, "value"));
            bool passed = threshold <= 10;

            var sb = new StringBuilder(passed
                ? "✅ Smart lockout threshold is set to 10 or below.\n\n"
                : "❌ Smart lockout threshold is configured above 10.\n\n");
            sb.Append($"## [Smart lockout configuration]({PortalLink})\n\n");
            sb.Append("| Setting | Value |\n");
            sb.Append("| :---- | :---- |\n");
            sb.Append($"| Lockout threshold | {threshold} attempts |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        private static long ParseInt(string? s)
        {
            if (string.IsNullOrEmpty(s)) return 0;
            if (long.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var l)) return l;
            if (double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var d))
                return (long)System.Math.Round(d, System.MidpointRounding.ToEven);
            return 0;
        }
    }
}
