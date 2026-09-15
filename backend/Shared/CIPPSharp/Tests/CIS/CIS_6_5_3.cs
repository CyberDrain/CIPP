using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (6.5.3) — Additional storage providers SHALL be restricted in Outlook on the web.
    /// Port of Invoke-CippTestCIS_6_5_3. Reads the default OWA mailbox policy; passes when
    /// AdditionalStorageProvidersAvailable is false.
    /// </summary>
    public sealed class CIS_6_5_3 : ICippTest
    {
        public string Id => "CIS_6_5_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("OwaMailboxPolicy"))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "OwaMailboxPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var d = PickOwaDefault(data)!.Value;

            if (IsFalse(d, "AdditionalStorageProvidersAvailable"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Additional storage providers are disabled on '{Str(d, "Identity")}'.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Additional storage providers are enabled on '{Str(d, "Identity")}' (AdditionalStorageProvidersAvailable: {Cell(Prop(d, "AdditionalStorageProvidersAvailable"))}).");
        }
    }
}
