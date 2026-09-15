using System.Globalization;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Smart lockout duration is set to a minimum of 60.
    /// Port of Invoke-CippTestZTNA21849. Reads the 'Password Rule Settings' record from the Settings
    /// cache; a missing template or missing LockoutDurationInSeconds value is treated as the 60s default
    /// (Passed). Otherwise Passed when the configured duration is >= 60. Never Skipped.
    /// </summary>
    public sealed class ZTNA21849 : ICippTest
    {
        public string Id => "ZTNA21849";

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
                return DefaultResult();

            JsonElement setting = default;
            bool haveSetting = false;
            foreach (var v in Arr(rule, "values"))
                if (StrEq(v, "name", "LockoutDurationInSeconds")) { setting = v; haveSetting = true; break; }

            if (!haveSetting)
                return DefaultResult();

            long duration = ParseInt(Str(setting, "value"));
            bool passed = duration >= 60;

            var sb = new StringBuilder(passed
                ? "✅ Smart Lockout duration is configured to 60 seconds or higher.\n\n"
                : "❌ Smart Lockout duration is configured below 60 seconds.\n\n");
            sb.Append($"## [Smart Lockout Settings]({PortalLink})\n\n");
            sb.Append("| Setting | Value |\n");
            sb.Append("| :---- | :---- |\n");
            sb.Append($"| Lockout Duration (seconds) | {duration} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        private static CippTestResult DefaultResult()
        {
            var sb = new StringBuilder("✅ Smart Lockout duration is configured to 60 seconds or higher (default).\n\n");
            sb.Append($"## [Smart Lockout Settings]({PortalLink})\n\n");
            sb.Append("| Setting | Value |\n");
            sb.Append("| :---- | :---- |\n");
            sb.Append("| Lockout Duration (seconds) | 60 (Default) |\n");
            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }

        // Mirrors PS [int] on a string/number value (0 when unparseable).
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
