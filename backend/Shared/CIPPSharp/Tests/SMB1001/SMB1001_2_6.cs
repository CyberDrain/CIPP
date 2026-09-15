using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.6) — MFA enforced on all business applications. Port of
    /// Invoke-CippTestSMB1001_2_6. Single source: MFAState. Requires All-Apps CA coverage
    /// (CoveredByCA == 'Enforced - All Apps'); Specific-Apps coverage does not satisfy 2.6.
    /// </summary>
    public sealed class SMB1001_2_6 : ICippTest
    {
        public string Id => "SMB1001_2_6";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateMfaState(
                data,
                ca => !string.Equals(ca, "Enforced - All Apps", System.StringComparison.OrdinalIgnoreCase),
                n => $"All {n} active member account(s) have MFA enforced across all business applications.",
                (unp, tot) => $"{unp} of {tot} active member account(s) are not protected by an All-Apps MFA policy. Specific-Apps CA policies satisfy 2.5 (email) but not 2.6 (all business apps):");
    }
}
