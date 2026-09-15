using System.Collections.Generic;
using System.Linq;
using System.Text;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Advanced Spam Filter (ASF) options are turned off. Port of Invoke-CippTestORCA102.
    /// A policy fails if ANY of the ASF settings is 'On'. Single source: ExoHostedContentFilterPolicy.
    /// </summary>
    public sealed class ORCA102 : ICippTest
    {
        public string Id => "ORCA102";

        // Ordered field → short name map, matching the PS [ordered] hashtable used for the fail table.
        private static readonly (string Field, string Name)[] AsfSettings =
        {
            ("IncreaseScoreWithImageLinks", "ImageLinks"),
            ("IncreaseScoreWithNumericIps", "NumericIPs"),
            ("IncreaseScoreWithRedirectToOtherPort", "RedirectToOtherPort"),
            ("IncreaseScoreWithBizOrInfoUrls", "BizOrInfoUrls"),
            ("MarkAsSpamEmptyMessages", "EmptyMessages"),
            ("MarkAsSpamJavaScriptInHtml", "JavaScript"),
            ("MarkAsSpamFramesInHtml", "Frames"),
            ("MarkAsSpamObjectTagsInHtml", "ObjectTags"),
            ("MarkAsSpamEmbedTagsInHtml", "EmbedTags"),
            ("MarkAsSpamFormTagsInHtml", "FormTags"),
            ("MarkAsSpamWebBugsInHtml", "WebBugs"),
            ("MarkAsSpamSensitiveWordList", "SensitiveWordList"),
            ("MarkAsSpamSpfRecordHardFail", "SpfRecordHardFail"),
            ("MarkAsSpamFromAddressAuthFail", "FromAddressAuthFail"),
            ("MarkAsSpamNdrBackscatter", "NdrBackscatter"),
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("ExoHostedContentFilterPolicy"))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = Items(data.Get("ExoHostedContentFilterPolicy")).ToList();
            var failed = policies.Where(p => AsfSettings.Any(s => StrEq(p, s.Field, "On"))).ToList();
            int passedCount = policies.Count - failed.Count;

            if (failed.Count == 0)
            {
                var sb = new StringBuilder();
                sb.Append("All anti-spam policies have Advanced Spam Filter (ASF) options turned off.\n\n");
                sb.Append($"**Compliant Policies:** {passedCount}");
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            var f = new StringBuilder();
            f.Append($"{failed.Count} anti-spam policies have Advanced Spam Filter (ASF) options enabled.\n\n");
            f.Append($"**Non-Compliant Policies:** {failed.Count}\n\n");
            var rows = new List<IReadOnlyList<string>>();
            foreach (var p in failed)
            {
                var enabled = AsfSettings.Where(s => StrEq(p, s.Field, "On")).Select(s => s.Name);
                rows.Add(new[] { CellOf(p, "Identity"), string.Join(", ", enabled) });
            }
            f.Append(Markdown.Table(new[] { "Policy Name", "Enabled ASF Options" }, rows));
            return new CippTestResult(TestStatus.Failed, f.ToString());
        }
    }
}
