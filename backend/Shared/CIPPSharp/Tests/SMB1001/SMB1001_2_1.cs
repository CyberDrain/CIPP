using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.1) — Strong password hygiene: Entra ID password protection with a custom
    /// banned-password list. Port of Invoke-CippTestSMB1001_2_1. Single source: Settings (the
    /// 'Password Rule Settings' template).
    /// </summary>
    public sealed class SMB1001_2_1 : ICippTest
    {
        private const string PwdTemplateId = "5cf42378-d67d-4f36-ba46-e8b86229381d";

        public string Id => "SMB1001_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var settings = data.Get("Settings");
            if (!Any(settings))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Settings cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement pwd = default;
            foreach (var s in Items(settings))
            {
                if (StrEq(s, "templateId", PwdTemplateId) || StrEq(s, "displayName", "Password Rule Settings"))
                {
                    pwd = s;
                    break;
                }
            }

            if (pwd.ValueKind != JsonValueKind.Object)
            {
                return new CippTestResult(TestStatus.Failed,
                    "Entra ID Password Rule Settings not found. Configure a custom banned-password list to satisfy SMB1001 (2.1.vi) — passwords must not appear in previous data breaches.");
            }

            var enforce = ValueByName(pwd, "EnableBannedPasswordCheck");
            var custom = ValueByName(pwd, "BannedPasswordList");

            bool enforced = string.Equals(enforce, "True", System.StringComparison.OrdinalIgnoreCase);
            if (enforced && !string.IsNullOrWhiteSpace(custom))
            {
                int wordCount = custom!.Split('\t').Length;
                return new CippTestResult(TestStatus.Passed,
                    $"Custom banned passwords are enforced ({wordCount} banned term(s)).");
            }

            var lengthText = custom == null ? "" : custom.Length.ToString();
            return new CippTestResult(TestStatus.Failed,
                $"Entra ID Password Protection is not fully configured.\n\n- EnableBannedPasswordCheck: {enforce}\n- BannedPasswordList length: {lengthText}");
        }

        /// <summary>The .value of the first values[] entry whose name matches (case-insensitive), or null.</summary>
        private static string? ValueByName(JsonElement setting, string name)
        {
            foreach (var v in Arr(setting, "values"))
                if (StrEq(v, "name", name)) return Str(v, "value");
            return null;
        }
    }
}
