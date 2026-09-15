using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.5) — Weak authentication methods SHALL be disabled (SMS, Voice).
    /// Port of Invoke-CippTestCIS_5_2_3_5. An absent method counts as disabled.
    /// </summary>
    public sealed class CIS_5_2_3_5 : ICippTest
    {
        public string Id => "CIS_5_2_3_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var amp = data.Get("AuthenticationMethodsPolicy");
            if (!Any(amp))
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");

            var cfg = FirstOrNull(amp)!.Value;
            var configs = Path(cfg, "authenticationMethodConfigurations");
            var sms = FindInArray(configs, "id", "Sms");
            var voice = FindInArray(configs, "id", "Voice");

            var smsDisabled = sms == null || StrEq(sms.Value, "state", "disabled");
            var voiceDisabled = voice == null || StrEq(voice.Value, "state", "disabled");

            if (smsDisabled && voiceDisabled)
                return new CippTestResult(TestStatus.Passed,
                    "SMS and Voice authentication methods are both disabled.");

            var smsState = sms == null ? null : Str(sms.Value, "state");
            var voiceState = voice == null ? null : Str(voice.Value, "state");
            return new CippTestResult(TestStatus.Failed,
                $"Weak methods are still enabled.\n\n- SMS state: {smsState}\n- Voice state: {voiceState}");
        }
    }
}
