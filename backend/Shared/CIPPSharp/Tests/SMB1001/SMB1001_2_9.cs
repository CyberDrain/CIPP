using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// SMB1001 (2.9) — MFA enforced where important digital data is stored. Port of
    /// Invoke-CippTestSMB1001_2_9. Single source: MFAState. Same CA predicate as 2.5
    /// (CoveredByCA not 'Enforced*'); differs only in prose.
    /// </summary>
    public sealed class SMB1001_2_9 : ICippTest
    {
        public string Id => "SMB1001_2_9";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateMfaState(
                data,
                ca => !Like(ca, "Enforced*"),
                n => $"All {n} active member account(s) accessing data-storing workloads are protected by MFA.",
                (unp, tot) => $"{unp} of {tot} active member account(s) can access data-storing workloads (SharePoint, OneDrive, Exchange) without MFA:");
    }
}
