namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (Restrict Admin Privileges) — PIM activation requires approval for Global Administrator
    /// and Privileged Role Administrator. Port of Invoke-CippTestE8_Admin_10. Manual/informational
    /// task; always Informational.
    /// </summary>
    public sealed class E8_Admin_10 : ICippTest
    {
        public string Id => "E8_Admin_10";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm Global Administrator and Privileged Role Administrator activations require approval (PIM > Role settings > Activation > Require approval to activate). The full PIM rule set is not exposed in the cached `RoleManagementPolicies` collection.");
    }
}
