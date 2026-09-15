using System.Collections.Generic;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.1.1) — External file sharing in Teams SHALL be enabled for only approved cloud
    /// storage services. Port of Invoke-CippTestCIS_8_1_1. Passes when no third-party cloud storage
    /// provider (Dropbox / Box / Google Drive / ShareFile / Egnyte) is enabled.
    /// </summary>
    public sealed class CIS_8_1_1 : ICippTest
    {
        public string Id => "CIS_8_1_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var client = data.Get("CsTeamsClientConfiguration");
            if (!Any(client))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "CsTeamsClientConfiguration cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(client)!.Value;
            var enabled = new List<string>();
            if (PsTruthyProp(cfg, "AllowDropbox")) enabled.Add("Dropbox");
            if (PsTruthyProp(cfg, "AllowBox")) enabled.Add("Box");
            if (PsTruthyProp(cfg, "AllowGoogleDrive")) enabled.Add("GoogleDrive");
            if (PsTruthyProp(cfg, "AllowShareFile")) enabled.Add("ShareFile");
            if (PsTruthyProp(cfg, "AllowEgnyte")) enabled.Add("Egnyte");

            if (enabled.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "No third-party cloud storage providers are enabled in Teams.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Third-party cloud storage providers are enabled in Teams: {string.Join(", ", enabled)}.");
        }
    }
}
