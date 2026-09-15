namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (Restrict Admin Privileges) — PIM activation requires MFA and justification. Port of
    /// Invoke-CippTestE8_Admin_09. Manual/informational task; always Informational.
    /// </summary>
    public sealed class E8_Admin_09 : ICippTest
    {
        public string Id => "E8_Admin_09";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. In Entra ID > PIM > Microsoft Entra roles > Settings, confirm each highly-privileged role requires MFA on activation and a justification. The full PIM rule set is not exposed in cached `RoleManagementPolicies` (rules require `$expand=rules` per role).");
    }
}
