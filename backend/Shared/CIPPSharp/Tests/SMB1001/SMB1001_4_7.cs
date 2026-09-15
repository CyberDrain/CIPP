namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (4.7) — Secure disposal of devices storing sensitive information. Physical
    /// disposal is outside M365. Port of Invoke-CippTestSMB1001_4_7 — constant Informational.
    /// </summary>
    public sealed class SMB1001_4_7 : ICippTest
    {
        public string Id => "SMB1001_4_7";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. SMB1001 (4.7) requires devices that store sensitive, private, or confidential information to be disposed of securely — by physical destruction (shredder or external service) or non-recoverable formatting if the device is reused or sold. Evidence the disposal procedure (destruction certificates, asset disposal log) to your Dynamic Standard Certifier separately. Configuring an Intune managed-device cleanup rule helps remove corporate data from inactive devices but does not satisfy the physical-disposal requirement on its own.");
    }
}
