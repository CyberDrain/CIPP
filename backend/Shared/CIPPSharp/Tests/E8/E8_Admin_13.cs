namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Restrict Admin Privileges) — high-privilege OAuth grants are reviewed. Port of
    /// Invoke-CippTestE8_Admin_13. Manual/informational task; always Informational.
    /// </summary>
    public sealed class E8_Admin_13 : ICippTest
    {
        public string Id => "E8_Admin_13";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Review enterprise applications and OAuth2 permission grants for high-privilege scopes (Directory.ReadWrite.All, RoleManagement.ReadWrite.Directory, Application.ReadWrite.All, Mail.ReadWrite, full_access_as_app). The OAuth2PermissionGrants and ServicePrincipals collections are not currently cached for analysis here; use the CIPP *Application Approvals* and *Enterprise Applications* views instead.");
    }
}
