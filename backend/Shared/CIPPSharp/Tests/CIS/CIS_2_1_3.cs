using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (2.1.3) — Notifications for internal users sending malware SHALL be enabled.
    /// Port of Invoke-CippTestCIS_2_1_3. Accepts any policy (not only the default) that has the
    /// internal-sender admin notification configured.
    /// </summary>
    public sealed class CIS_2_1_3 : ICippTest
    {
        public string Id => "CIS_2_1_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ExoMalwareFilterPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.");
            }

            JsonElement? compliant = null;
            foreach (var p in policies.EnumerateArray())
            {
                if (IsTrue(p, "EnableInternalSenderAdminNotifications")
                    && !string.IsNullOrWhiteSpace(Str(p, "InternalSenderAdminAddress")))
                {
                    compliant = p;
                    break;
                }
            }

            if (compliant != null)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Internal sender admin notifications enabled on '{Str(compliant.Value, "Identity")}'. Recipient: {Str(compliant.Value, "InternalSenderAdminAddress")}.");
            }

            JsonElement? def = null;
            foreach (var p in policies.EnumerateArray())
                if (IsTrue(p, "IsDefault")) { def = p; break; }
            if (def == null) def = FirstOrNull(policies);
            var d = def!.Value;

            return new CippTestResult(TestStatus.Failed,
                $"Internal sender admin notifications are not configured on '{Str(d, "Identity")}'.\n\n- EnableInternalSenderAdminNotifications: {Cell(Prop(d, "EnableInternalSenderAdminNotifications"))}\n- InternalSenderAdminAddress: '{Str(d, "InternalSenderAdminAddress")}'");
        }
    }
}
