using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 7.0.0 (2.1.7) — An anti-phishing policy SHALL be created (CIS L2 settings).
    /// The DefenderForOffice365 license gate is handled by the engine/dispatcher (registry
    /// requiredCapabilities → Unlicensed), so this body only runs when licensed and is pure
    /// cache logic: ExoAntiPhishPolicies joined to ExoAntiPhishRules by policy name.
    /// </summary>
    public sealed class CIS_2_1_7 : ICippTest
    {
        public string Id => "CIS_2_1_7";

        private static bool ActionOk(JsonElement policy, string field)
            => CippTestHelpers.StrEq(policy, field, "Quarantine")
            || CippTestHelpers.StrEq(policy, field, "MoveToJmf");

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoAntiPhishPolicies");
            if (!CippTestHelpers.Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoAntiPhishPolicies cache not found. Please refresh the cache for this tenant.");
            }

            // A custom policy's active state lives on its anti-phish RULE's State, joined by
            // AntiPhishPolicy name (mirrors Invoke-CIPPStandardAntiPhishPolicy). Only the built-in
            // default policy carries Enabled itself.
            var enabledRulePolicies = new HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
            foreach (var rule in CippTestHelpers.Items(data.Get("ExoAntiPhishRules")))
            {
                if (CippTestHelpers.StrEq(rule, "State", "Enabled"))
                {
                    var name = CippTestHelpers.Str(rule, "AntiPhishPolicy");
                    if (!string.IsNullOrEmpty(name)) enabledRulePolicies.Add(name!);
                }
            }

            var compliant = new List<string>();
            foreach (var p in CippTestHelpers.Items(policies))
            {
                var name = CippTestHelpers.Str(p, "Name");
                var active = CippTestHelpers.IsTrue(p, "Enabled")
                          || (name != null && enabledRulePolicies.Contains(name));
                if (active &&
                    CippTestHelpers.Int(p, "PhishThresholdLevel") >= 2 &&
                    CippTestHelpers.IsTrue(p, "EnableMailboxIntelligenceProtection") &&
                    CippTestHelpers.IsTrue(p, "EnableMailboxIntelligence") &&
                    CippTestHelpers.IsTrue(p, "EnableSpoofIntelligence") &&
                    ActionOk(p, "TargetedUserProtectionAction") &&
                    ActionOk(p, "MailboxIntelligenceProtectionAction") &&
                    ActionOk(p, "TargetedDomainProtectionAction") &&
                    ActionOk(p, "AuthenticationFailAction") &&
                    CippTestHelpers.IsTrue(p, "EnableFirstContactSafetyTips") &&
                    CippTestHelpers.IsTrue(p, "EnableSimilarUsersSafetyTips") &&
                    CippTestHelpers.IsTrue(p, "EnableSimilarDomainsSafetyTips") &&
                    CippTestHelpers.IsTrue(p, "EnableUnusualCharactersSafetyTips"))
                {
                    compliant.Add(name ?? "(unnamed)");
                }
            }

            if (compliant.Count > 0)
            {
                var body = $"{compliant.Count} anti-phishing policy/policies meet CIS L2 requirements:\n\n"
                         + string.Join("\n", compliant.Select(n => $"- {n}"));
                return new CippTestResult(TestStatus.Passed, body);
            }

            return new CippTestResult(TestStatus.Failed,
                "No anti-phishing policy meets every CIS requirement (PhishThreshold>=2, all impersonation/intelligence/safety tips on, quarantine actions configured).");
        }
    }
}
