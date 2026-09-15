using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Secure Score Report — 14-day trend of Microsoft Secure Score.
    /// Port of Invoke-CippTestGenericTest009. Single source: SecureScore. Always Informational
    /// (Skipped when the cache is empty).
    /// </summary>
    public sealed class GenericTest009 : ICippTest
    {
        public string Id => "GenericTest009";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var scoreData = data.Get("SecureScore");
            if (!Any(scoreData))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "No Secure Score data found in the reporting database. Please sync the Secure Score cache first.");
            }

            var scores = scoreData.EnumerateArray().Where(s => HasValue(s, "currentScore")).ToList();
            if (scores.Count == 0)
            {
                return new CippTestResult(TestStatus.Informational,
                    "Secure Score data was found but contained no score records.");
            }

            var sorted = scores
                .OrderBy(s => ParseDate(Str(s, "createdDateTime")))
                .ToList();

            var latest = sorted[sorted.Count - 1];
            var oldest = sorted[0];
            double currentScore = Round1(Dbl(latest, "currentScore"));
            double maxScore = Round1(Dbl(latest, "maxScore"));
            double scorePct = maxScore > 0 ? Round1(currentScore / maxScore * 100) : 0;

            double oldestScore = Round1(Dbl(oldest, "currentScore"));
            double scoreChange = Round1(currentScore - oldestScore);
            string trendIcon = scoreChange > 0 ? $"📈 +{Fmt(scoreChange)}"
                : scoreChange < 0 ? $"📉 {Fmt(scoreChange)}"
                : "➡️ No change";

            var sb = new StringBuilder();
            sb.Append("### Current Score\n\n");
            sb.Append("| Metric | Value |\n");
            sb.Append("|--------|-------|\n");
            sb.Append($"| Current Score | **{Fmt(currentScore)}** out of {Fmt(maxScore)} ({Fmt(scorePct)}%) |\n");
            sb.Append($"| 14-Day Trend | {trendIcon} |\n");
            sb.Append($"| Data Points | {sorted.Count} days |\n\n");

            if (scorePct >= 80)
                sb.Append("**✅ Strong security posture.** Your score is in the top tier. Keep monitoring to maintain this level.\n\n");
            else if (scorePct >= 50)
                sb.Append("**🟡 Moderate security posture.** There's room for improvement. Review the recommended actions in your Microsoft 365 Security portal.\n\n");
            else
                sb.Append("**🔴 Low security posture.** Significant improvements are recommended. Focus on the high-impact actions first.\n\n");

            sb.Append("### 14-Day Score Trend\n\n");
            sb.Append("| Date | Score | Max Score | Percentage |\n");
            sb.Append("|------|-------|-----------|------------|\n");

            foreach (var score in sorted)
            {
                var created = Str(score, "createdDateTime");
                string dateStr = !string.IsNullOrEmpty(created)
                    && DateTime.TryParse(created, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt)
                        ? dt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                        : "Unknown";
                double dayScore = Round1(Dbl(score, "currentScore"));
                double dayMax = Round1(Dbl(score, "maxScore"));
                double dayPct = dayMax > 0 ? Round1(dayScore / dayMax * 100) : 0;
                sb.Append($"| {dateStr} | {Fmt(dayScore)} | {Fmt(dayMax)} | {Fmt(dayPct)}% |\n");
            }

            // Top improvable controls from the latest snapshot.
            var improvable = new List<(string Name, double Score, double Max, double Gap)>();
            foreach (var control in RecordsOf(latest, "controlScores"))
            {
                if (!HasValue(control, "score")) continue;
                var maxNum = Num(control, "maxScore");
                double maxControl = (maxNum.HasValue && maxNum.Value != 0) ? maxNum.Value : 0;
                double current = Dbl(control, "score");
                double gap = maxControl - current;
                if (gap <= 0) continue;
                string name = Regex.Replace(Str(control, "controlName") ?? "", "([a-z])([A-Z])", "$1 $2");
                improvable.Add((name, current, maxControl, gap));
            }

            var top = improvable.OrderByDescending(c => c.Gap).Take(10).ToList();
            if (top.Count > 0)
            {
                sb.Append("\n### Top Improvement Opportunities\n\n");
                sb.Append("| Control | Current | Max | Points Available |\n");
                sb.Append("|---------|---------|-----|-----------------|\n");
                foreach (var c in top)
                    sb.Append($"| {c.Name} | {Fmt(c.Score)} | {Fmt(c.Max)} | +{Fmt(c.Gap)} |\n");
            }

            return new CippTestResult(TestStatus.Informational, sb.ToString());
        }

        private static DateTime ParseDate(string? s)
            => !string.IsNullOrEmpty(s)
               && DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt)
                ? dt : DateTime.MinValue;
    }
}
