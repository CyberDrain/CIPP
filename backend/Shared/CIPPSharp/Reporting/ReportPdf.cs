using System;
using System.Collections.Generic;
using System.Text.Json;
using OfficeIMO;
using OfficeIMO.Pdf;

namespace CIPP.Reporting
{
    /// <summary>
    /// Entry point for server-side report rendering. Called from PowerShell as
    /// <c>[CIPP.Reporting.ReportPdf]::Render(...)</c> (wrapped by ConvertTo-CippReportPdf.ps1).
    /// Takes the declarative component tree + branding + variables and returns the finished PDF bytes,
    /// composing the OfficeIMO document from the shared component kit - cover page, then content
    /// sections carrying header / footer / page numbers / watermark, with hero pages and page breaks
    /// splitting the flow (buildPageGroups equivalent).
    /// </summary>
    public static class ReportPdf
    {
        public static byte[] Render(
            string blocksJson,
            string brandingJson,
            string variablesJson,
            string tenantName,
            string reportName,
            string generatedOn,
            string pageSize = "A4",
            bool landscape = false,
            bool chrome = true)
        {
            ReportMarkdown.RenderEmojiGlyphs = EmojiFontBytes.Value is { Length: > 0 };
            ReportMarkdown.EmojiCoverage = ReportMarkdown.RenderEmojiGlyphs ? EmojiCoverageSet.Value : new HashSet<int>();
            // Colour emoji render as bundled Twemoji inline images when the asset set is present; the
            // monochrome font remains the fallback for anything not bundled (and for drawing contexts).
            ReportMarkdown.RenderEmojiImages = TwemojiAssets.Enabled;
            var blocks = ReportNode.ParseTree(blocksJson);
            var theme = ReportTheme.Create(BrandingInput.FromJson(brandingJson));
            var branding = BrandingInput.FromJson(brandingJson);

            var variables = ParseVariables(variablesJson);
            variables["tenantname"] = tenantName ?? "Organization";
            variables["reportname"] = reportName ?? "Report";
            variables["reportdate"] = generatedOn ?? string.Empty;

            var ctx = new ReportContext
            {
                Theme = theme,
                Variables = variables,
                PageSize = string.IsNullOrWhiteSpace(pageSize) ? "A4" : pageSize,
                Landscape = landscape,
                TenantName = tenantName ?? "Organization",
                ReportName = reportName ?? "Report",
                GeneratedOn = generatedOn ?? string.Empty,
                Logo = ReportComponents.DecodeImage(branding.Logo),
                // Branding's own cover photo wins; otherwise a report can name a bundled stock cover via
                // the %coverfallbackimage% variable (e.g. "/reportImages/soc.jpg"), mirroring the client's
                // resolveCoverImage fallback so a report without configured branding still gets a cover.
                CoverImage = ReportComponents.DecodeImage(branding.CoverImage)
                    ?? (variables.TryGetValue("coverfallbackimage", out var coverFallback) ? ReportComponents.DecodeImage(coverFallback) : null),
            };

            var groups = BuildPageGroups(blocks);
            // Branding's configured footer wins; a report's own %footerlabel% is the fallback (client
            // PageFooter's `label`), so a fixed report still identifies itself when no branding footer is set.
            var footerText = theme.FooterEnabled
                ? ReportTheme.ApplyFooter(theme.FooterTemplate, variables)
                : (variables.TryGetValue("footerlabel", out var fl) ? ReportTheme.ApplyFooter(fl, variables) : string.Empty);
            var watermark = theme.WatermarkEnabled ? ReportTheme.ApplyWatermark(theme.WatermarkText, variables) : string.Empty;

            var doc = PdfDocument.Create(compose =>
            {
                compose.Defaults(p =>
                {
                    p.Size(ResolveSize(ctx.PageSize));
                    if (ctx.Landscape) p.Landscape();
                    p.Margin(ReportStyles.PagePadding);
                });

                // Cover - its own page, no header/footer/watermark. Skipped in chrome-less mode (used by
                // the component A/B harness and any embedded/preview render that wants only the content).
                // A cover photo (branding) fills the page behind the drawn cover content.
                if (chrome)
                    compose.Page(p =>
                    {
                        p.Background(ReportComponents.Pdf(ReportColours.White));
                        if (ctx.CoverImage is { Length: > 0 })
                        {
                            try { p.BackgroundImage(ctx.CoverImage, OfficeIMO.Drawing.OfficeImageFit.Cover, 0.5); }
                            catch { /* an unusable cover photo leaves the plain white cover */ }
                        }
                        p.Content(cc => cc.Item(i => ReportComponents.RenderCoverDrawing(ctx, i)));
                    });

                foreach (var group in groups)
                {
                    if (group.Kind == "hero")
                    {
                        // Full-bleed divider: a dark page with an optional cover photo behind the big figure,
                        // no header/footer chrome. The photo is a page background image (edge to edge); the
                        // text is drawn over it, vertically centred, with the footer note bottom-right.
                        var heroImage = ReportComponents.DecodeImage(group.Block!.Str("heroImage") ?? group.Block!.Str("backgroundImage"));
                        compose.Section(p =>
                        {
                            p.Background(ReportComponents.Pdf(ctx.Theme.Palette["infographicBackground"]));
                            if (heroImage is { Length: > 0 })
                            {
                                try { p.BackgroundImage(heroImage, OfficeIMO.Drawing.OfficeImageFit.Cover, 0.28); }
                                catch { /* an unusable cover photo leaves the plain dark page */ }
                            }
                            p.Content(cc => cc.Item(i => ReportComponents.RenderHeroDrawing(ctx, i, group.Block!)));
                        });
                        continue;
                    }
                    compose.Section(p =>
                    {
                        if (chrome) ApplyContentChrome(p, ctx, footerText, watermark);
                        p.Content(cc => cc.Item(i =>
                        {
                            // A titled group (a fixed report's ContentPage) heads with its own title and
                            // subtitle; the Report Builder path has neither, so it falls back to the report
                            // name and the generated-on date.
                            if (chrome) RenderPageHeader(ctx, i, group.Title ?? ctx.ReportName, group.Subtitle ?? ctx.GeneratedOn);
                            var firstBlock = true;
                            foreach (var block in group.Blocks) { ReportComponents.RenderBlock(ctx, i, block, firstBlock); firstBlock = false; }
                        }));
                    });
                }
            }, BuildOptions());

            return doc.ToBytes();
        }

        // PDF options carrying the emoji fallback font: the standard fonts have no glyph for any emoji, so a
        // bundled monochrome symbol/emoji font is registered as a Unicode fallback and OfficeIMO routes each
        // emoji code point through it (per character - the surrounding text stays in the standard font), in
        // table cells and paragraphs alike. The report's three status emoji are tinted per run downstream;
        // everything else renders in the surrounding text colour.
        private static PdfOptions BuildOptions()
        {
            var options = new PdfOptions();
            var font = EmojiFontBytes.Value;
            var coverage = EmojiCoverageSet.Value;
            if (font is { Length: > 0 } && coverage.Count > 0)
            {
                // OfficeIMO embeds only the glyphs a given report actually uses, compressed, so a report
                // gains a few KB, not the whole ~800 KB font. The fallback is scoped to exactly the code
                // points the font carries above U+00FF (the Latin-1 glyphs it also holds exist only so
                // OfficeIMO's greedy neighbour-of-an-emoji fallback never lands on an uncovered character),
                // so ordinary text always stays in the standard font.
                var ranges = new OfficeIMO.Drawing.OfficeFontUnicodeRangeSet(CoverageRanges(coverage));
                options.CompressEmbeddedFonts = true;
                options.EmbeddedFontFallbacks = new PdfEmbeddedFontFallbackSet(
                    new[] { new PdfEmbeddedFontFallbackCandidate("CippReportEmoji", font, ranges) });
            }
            return options;
        }

        // The coverage set compressed into [start,end] ranges for the fallback scope. The emoji blocks are
        // scattered, so this coalesces across the smallest gaps until within OfficeIMO's 1..128-range limit.
        // Widening a range is safe: it only ever includes unassigned/uncovered code points, which Sanitize
        // (gated on the exact coverage set) never keeps, so no uncovered character is routed to the fallback.
        private const int MaxFallbackRanges = 128;
        private static OfficeIMO.Drawing.OfficeFontUnicodeRange[] CoverageRanges(HashSet<int> coverage)
        {
            var sorted = new List<int>(coverage);
            sorted.Sort();
            var ranges = new List<(int start, int end)>();
            var start = sorted[0];
            var prev = sorted[0];
            for (var k = 1; k < sorted.Count; k++)
            {
                if (sorted[k] == prev + 1) { prev = sorted[k]; continue; }
                ranges.Add((start, prev));
                start = prev = sorted[k];
            }
            ranges.Add((start, prev));

            while (ranges.Count > MaxFallbackRanges)
            {
                var mergeAt = 0;
                var smallestGap = int.MaxValue;
                for (var k = 0; k < ranges.Count - 1; k++)
                {
                    var gap = ranges[k + 1].start - ranges[k].end;
                    if (gap < smallestGap) { smallestGap = gap; mergeAt = k; }
                }
                ranges[mergeAt] = (ranges[mergeAt].start, ranges[mergeAt + 1].end);
                ranges.RemoveAt(mergeAt + 1);
            }
            return ranges.ConvertAll(r => new OfficeIMO.Drawing.OfficeFontUnicodeRange(r.start, r.end)).ToArray();
        }

        // Exactly the emoji code points the bundled font can draw (above U+00FF, minus the CP1252 specials
        // the standard fonts render): the single source of truth for what Sanitize keeps and which ranges
        // OfficeIMO routes to the fallback. Read once from the font's own cmap so the two never drift.
        private static readonly Lazy<HashSet<int>> EmojiCoverageSet = new(() =>
        {
            var set = new HashSet<int>();
            var font = EmojiFontBytes.Value;
            if (font is not { Length: > 0 }) return set;
            try
            {
                foreach (var cp in FontCmap.ReadCodepoints(font))
                    if (cp > 0xFF && !ReportMarkdown.IsWinAnsiSpecial(cp)) set.Add(cp);
            }
            catch { set.Clear(); }
            return set;
        });

        // The fallback font ships next to the assembly as emoji-fallback.ttf (copied by the build, like the
        // OfficeIMO DLLs). Loaded once; absence just means the emoji fall back to nothing rather than throwing.
        private static readonly Lazy<byte[]?> EmojiFontBytes = new(() =>
        {
            try
            {
                var dir = System.IO.Path.GetDirectoryName(typeof(ReportPdf).Assembly.Location);
                if (string.IsNullOrEmpty(dir)) return null;
                var path = System.IO.Path.Combine(dir, "emoji-fallback.ttf");
                return System.IO.File.Exists(path) ? System.IO.File.ReadAllBytes(path) : null;
            }
            catch { return null; }
        });

        // The styled page header (big title + subtitle + brand rule) that opens each content group,
        // matching the client's ContentPage header. Rendered as content rather than a running header so
        // it can carry the brand-coloured rule the running-header API can't draw.
        private static void RenderPageHeader(ReportContext ctx, PdfItemCompose item, string? title, string? subtitle)
        {
            // Title and subtitle read as one unit (client pageTitle marginBottom 8), so the title line box
            // is kept tight - the default paragraph line height otherwise balloons the gap between them -
            // then the client paddingBottom 8 before the brand rule, and marginBottom 14 after it.
            var titleColour = ctx.Theme.Palette["title"];
            item.Paragraph(b => { b.FontSize(ReportStyles.PageTitle); ReportComponents.EmitInline(b, title ?? ctx.ReportName, titleColour, ReportStyles.PageTitle, bold: true); },
                PdfAlign.Left, null, new PdfParagraphStyle { LineHeight = 1.0, SpacingAfter = 3 });
            if (!string.IsNullOrEmpty(subtitle))
            {
                var subtitleColour = ctx.Theme.Palette["subtitle"];
                item.Paragraph(b => { b.FontSize(ReportStyles.PageSubtitle); ReportComponents.EmitInline(b, subtitle, subtitleColour, ReportStyles.PageSubtitle); },
                    PdfAlign.Left, null, new PdfParagraphStyle { LineHeight = 1.05, SpacingAfter = 3 });
            }
            // Full-width brand rule under the header (HR auto-fits the content width; a fixed-width
            // rectangle risks exceeding it).
            item.HR(2, ReportComponents.Pdf(ctx.Theme.Palette["heading"]));
            item.Spacer(8);
        }

        private static void ApplyContentChrome(PdfPageCompose p, ReportContext ctx, string footerText, string watermark)
        {
            if (ctx.Theme.FooterShow || ctx.Theme.ShowPageNumbers)
            {
                p.Footer(f =>
                {
                    f.Color(ReportComponents.Pdf(ctx.Theme.Palette["footer"])).FontSize(ReportStyles.FooterText);
                    var showText = ctx.Theme.FooterShow && !string.IsNullOrEmpty(footerText);
                    var safeFooter = ReportMarkdown.Sanitize(footerText);
                    if (ctx.Theme.ShowPageNumbers)
                        f.Text(b =>
                        {
                            if (showText) b.Text(safeFooter + "   -   ");
                            b.Text("Page ").CurrentPage().Text(" of ").TotalPages();
                        });
                    else if (showText)
                        f.Text(safeFooter);
                });
            }
            if (!string.IsNullOrEmpty(watermark))
                p.Watermark(watermark, 0.08, ReportComponents.Pdf(ctx.Theme.Palette["watermark"]));
        }

        private sealed class PageGroup
        {
            public string Kind = "content"; // content|hero
            public List<ReportNode> Blocks = new();
            public ReportNode? Block;
            public string? Title;    // a fixed report's ContentPage title (null -> report name)
            public string? Subtitle; // its descriptive subtitle (null -> generated-on date)
        }

        private static List<PageGroup> BuildPageGroups(List<ReportNode> blocks)
        {
            var groups = new List<PageGroup>();
            var current = new PageGroup();
            void Flush() { if (current.Blocks.Count > 0) { groups.Add(current); current = new PageGroup { Title = null, Subtitle = null }; } }
            foreach (var block in blocks)
            {
                if (block.Type == "pagebreak") { Flush(); continue; }
                if (block.Type == "hero") { Flush(); groups.Add(new PageGroup { Kind = "hero", Block = block }); current = new PageGroup(); continue; }
                // A 'page' block opens a new titled content page (a fixed report's ContentPage).
                if (block.Type == "page") { Flush(); current.Title = block.Str("title"); current.Subtitle = block.Str("subtitle"); continue; }
                current.Blocks.Add(block);
            }
            Flush();
            if (groups.Count == 0) groups.Add(new PageGroup());
            return groups;
        }

        private static PageSize ResolveSize(string size) => (size ?? "A4").ToUpperInvariant() switch
        {
            "LETTER" => PageSizes.Letter,
            "LEGAL" => PageSizes.Legal,
            "A3" => PageSizes.A3,
            "A5" => PageSizes.A5,
            _ => PageSizes.A4,
        };

        private static Dictionary<string, string> ParseVariables(string? json)
        {
            var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrWhiteSpace(json)) return dict;
            try
            {
                var root = JsonDocument.Parse(json).RootElement;
                if (root.ValueKind == JsonValueKind.Object)
                    foreach (var p in root.EnumerateObject())
                        if (p.Value.ValueKind == JsonValueKind.String) dict[p.Name] = p.Value.GetString()!;
                        else if (p.Value.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False) dict[p.Name] = p.Value.ToString();
            }
            catch { /* leave empty */ }
            return dict;
        }
    }
}
