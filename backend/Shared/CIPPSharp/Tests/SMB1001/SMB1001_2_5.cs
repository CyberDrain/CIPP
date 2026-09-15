using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.5) — MFA enforced on all employee email accounts. Port of
    /// Invoke-CippTestSMB1001_2_5. Single source: MFAState. Unprotected when CA coverage is not
    /// 'Enforced*' and Security Defaults / per-user MFA are also off.
    /// </summary>
    public sealed class SMB1001_2_5 : ICippTest
    {
        public string Id => "SMB1001_2_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateMfaState(
                data,
                ca => !Like(ca, "Enforced*"),
                n => $"All {n} active member account(s) are protected by MFA (Conditional Access, Security Defaults, or per-user MFA).",
                (unp, tot) => $"{unp} of {tot} active member account(s) are not protected by any MFA enforcement mechanism:");
    }
}
