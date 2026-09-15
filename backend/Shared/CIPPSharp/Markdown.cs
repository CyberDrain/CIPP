using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CIPP.Tests
{
    /// <summary>
    /// Small markdown helpers that mirror the formatting the current PowerShell tests produce:
    /// pipe tables (<c>| a | b |</c>), <c>Select -First N</c> truncation with a
    /// "Showing N of M" note, and the percentage/threshold arithmetic the threshold tests use.
    /// Cell escaping mirrors <c>ConvertTo-CippMarkdownCell</c> so display names containing
    /// pipes/newlines do not blow the row apart.
    /// </summary>
    public static class Markdown
    {
        private static readonly Regex NewlineRegex = new(@"\r?\n", RegexOptions.Compiled);

        /// <summary>
        /// Escape a value for a markdown table cell. Null → "". Backslashes first (they are the
        /// escape char the frontend parser honours, so a literal one must be doubled before the
        /// pipe escape adds more), then pipes → <c>\|</c>, then newlines collapsed to spaces.
        /// Matches ConvertTo-CippMarkdownCell exactly.
        /// </summary>
        public static string EscapeCell(object? value)
        {
            if (value == null) return "";
            var text = value.ToString();
            if (string.IsNullOrEmpty(text)) return "";
            text = text.Replace("\\", "\\\\").Replace("|", "\\|");
            text = NewlineRegex.Replace(text, " ");
            return text.Trim();
        }

        /// <summary>
        /// Build a pipe table: header row, <c>| --- | --- |</c> separator, then one row per
        /// entry. Every cell is escaped. Rows longer/shorter than the header are padded/clipped
        /// to the header width so columns stay aligned.
        /// </summary>
        public static string Table(IReadOnlyList<string> headers, IEnumerable<IReadOnlyList<string>> rows)
        {
            if (headers == null || headers.Count == 0) return "";
            var sb = new StringBuilder();

            sb.Append("| ");
            for (int i = 0; i < headers.Count; i++)
            {
                if (i > 0) sb.Append(" | ");
                sb.Append(EscapeCell(headers[i]));
            }
            sb.Append(" |\n");

            sb.Append("| ");
            for (int i = 0; i < headers.Count; i++)
            {
                if (i > 0) sb.Append(" | ");
                sb.Append("---");
            }
            sb.Append(" |\n");

            foreach (var row in rows)
            {
                sb.Append("| ");
                for (int i = 0; i < headers.Count; i++)
                {
                    if (i > 0) sb.Append(" | ");
                    var cell = (row != null && i < row.Count) ? row[i] : "";
                    sb.Append(EscapeCell(cell));
                }
                sb.Append(" |\n");
            }

            return sb.ToString();
        }

        /// <summary>
        /// The italic truncation note the PS tests append, e.g.
        /// <c>*Showing 50 of 312 users.*</c>. Returns "" when nothing was truncated
        /// (<paramref name="shown"/> ≥ <paramref name="total"/>).
        /// </summary>
        public static string TruncationNote(int shown, int total, string noun = "records")
        {
            if (shown >= total) return "";
            return string.Format(CultureInfo.InvariantCulture, "*Showing {0} of {1} {2}.*", shown, total, noun);
        }

        /// <summary>
        /// Percentage of <paramref name="active"/> out of <paramref name="total"/>, rounded to
        /// one decimal (mirrors <c>[math]::Round(($a/$t)*100,1)</c>). 0 when total is 0.
        /// </summary>
        public static double Percent(int active, int total)
        {
            if (total <= 0) return 0;
            // Default (banker's/ToEven) rounding to match PowerShell's [math]::Round(x, 1).
            return Math.Round((double)active / total * 100, 1);
        }

        /// <summary>
        /// Threshold evaluation the threshold tests perform: the rounded percentage plus whether
        /// it meets <paramref name="pctThreshold"/> (<c>&gt;=</c>). Returned as a value so the
        /// caller can both render the percentage and branch on the verdict.
        /// </summary>
        public static ThresholdResult Threshold(int active, int total, double pctThreshold)
        {
            var pct = Percent(active, total);
            return new ThresholdResult(active, total, pct, pct >= pctThreshold);
        }
    }

    /// <summary>Result of <see cref="Markdown.Threshold(int,int,double)"/>.</summary>
    public readonly record struct ThresholdResult(int Active, int Total, double Pct, bool Met);
}
