using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.2.2) — Communication with unmanaged Teams users SHALL be disabled.
    /// Port of Invoke-CippTestCIS_8_2_2. Joins CsExternalAccessPolicy + CsTenantFederationConfiguration.
    /// Passes when consumer (unmanaged) access is disabled either by policy or tenant-wide.
    /// </summary>
    public sealed class CIS_8_2_2 : ICippTest
    {
        public string Id => "CIS_8_2_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var external = data.Get("CsExternalAccessPolicy");
            var federation = data.Get("CsTenantFederationConfiguration");

            if (!Any(external) && !Any(federation))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (CsExternalAccessPolicy or CsTenantFederationConfiguration) not found.");
            }

            var e = FirstOrNull(external);
            var f = FirstOrNull(federation);

            bool blocked = (e.HasValue && IsFalse(e.Value, "EnableTeamsConsumerAccess"))
                || (f.HasValue && IsFalse(f.Value, "AllowTeamsConsumer"));

            var eConsumer = e.HasValue ? Cell(Prop(e.Value, "EnableTeamsConsumerAccess")) : "";
            var fConsumer = f.HasValue ? Cell(Prop(f.Value, "AllowTeamsConsumer")) : "";

            if (blocked)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Communication with unmanaged Teams users is blocked.\n\n- EnableTeamsConsumerAccess (policy): {eConsumer}\n- AllowTeamsConsumer (tenant): {fConsumer}");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Communication with unmanaged Teams users is allowed.\n\n- EnableTeamsConsumerAccess (policy): {eConsumer}\n- AllowTeamsConsumer (tenant): {fConsumer}");
        }
    }
}
