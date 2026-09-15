using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.5/2.6/2.9 Level 4+) — weak MFA factors (SMS, Voice, Email) disabled. Port of
    /// Invoke-CippTestSMB1001_2_5_L4. Single source: AuthenticationMethodsPolicy (first record).
    /// </summary>
    public sealed class SMB1001_2_5_L4 : ICippTest
    {
        public string Id => "SMB1001_2_5_L4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var amp = data.Get("AuthenticationMethodsPolicy");
            if (!Any(amp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "AuthenticationMethodsPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = First(amp);
            var weak = new List<string>();
            foreach (var (id, label) in new[] { ("Sms", "SMS"), ("Voice", "Voice"), ("Email", "Email") })
            {
                var method = FindById(cfg, id);
                if (method.ValueKind == JsonValueKind.Object && !StrEq(method, "state", "disabled"))
                    weak.Add($"{label} ({Str(method, "state")})");
            }

            if (weak.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "SMS, Voice and Email authentication methods are all disabled. Phishing-resistant factors (Authenticator app, FIDO2, Hardware OATH) are the only paths.");
            }

            var body = "Level 4/5 of SMB1001 prohibits SMS/Voice/Email as MFA factors. The following weak methods remain enabled:\n\n- "
                       + string.Join("\n- ", weak)
                       + "\n\nDisable each via the Authentication Methods Policy.";
            return new CippTestResult(TestStatus.Failed, body);
        }

        private static JsonElement FindById(JsonElement cfg, string id)
        {
            foreach (var m in Arr(cfg, "authenticationMethodConfigurations"))
                if (StrEq(m, "id", id)) return m;
            return default;
        }
    }
}
