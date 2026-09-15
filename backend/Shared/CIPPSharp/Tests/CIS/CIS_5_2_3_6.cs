using System;
using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.3.6) — System-preferred multifactor authentication SHALL be enabled.
    /// Port of Invoke-CippTestCIS_5_2_3_6. systemCredentialPreferences.includeTargets is a list; the
    /// PS treats <c>.id</c>/<c>.targetType</c> as arrays, so any target matches.
    /// </summary>
    public sealed class CIS_5_2_3_6 : ICippTest
    {
        public string Id => "CIS_5_2_3_6";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var amp = data.Get("AuthenticationMethodsPolicy");
            if (!Any(amp))
                return new CippTestResult(TestStatus.Skipped, "AuthenticationMethodsPolicy cache not found.");

            var cfg = FirstOrNull(amp)!.Value;
            var state = LeafStr(Path(cfg, "systemCredentialPreferences", "state"));

            var targets = Path(cfg, "systemCredentialPreferences", "includeTargets");
            var ids = new List<string>();
            var types = new List<string>();
            if (targets.ValueKind == JsonValueKind.Array)
            {
                foreach (var t in targets.EnumerateArray())
                {
                    var id = Str(t, "id");
                    if (id != null) ids.Add(id);
                    var tt = Str(t, "targetType");
                    if (tt != null) types.Add(tt);
                }
            }
            else if (targets.ValueKind == JsonValueKind.Object)
            {
                var id = Str(targets, "id");
                if (id != null) ids.Add(id);
                var tt = Str(targets, "targetType");
                if (tt != null) types.Add(tt);
            }

            var targetId = string.Join(" ", ids);
            bool anyAllUsers = ids.Exists(i => string.Equals(i, "all_users", StringComparison.OrdinalIgnoreCase));
            bool anyGroup = types.Exists(t => string.Equals(t, "group", StringComparison.OrdinalIgnoreCase));

            if (string.Equals(state, "enabled", StringComparison.OrdinalIgnoreCase) && (anyAllUsers || anyGroup))
                return new CippTestResult(TestStatus.Passed, $"System-preferred MFA is enabled (target: {targetId}).");

            return new CippTestResult(TestStatus.Failed,
                $"System-preferred MFA is not enabled. state: {state}, target: {targetId}");
        }
    }
}
