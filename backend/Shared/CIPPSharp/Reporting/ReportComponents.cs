using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using OfficeIMO.Drawing;
using OfficeIMO.Pdf;

namespace CIPP.Reporting
{
    /// <summary>
    /// The reusable component kit - the server port of reportPdfPrimitives.jsx. Every component takes the
    /// <see cref="ReportContext"/> (theme/styles/variables) and the current OfficeIMO <see cref="PdfItemCompose"/>,
    /// and encapsulates all OfficeIMO calls. Reports compose these; no report inlines a raw OfficeIMO call.
    /// </summary>
    public static class ReportComponents
    {
        private const double CodeParagraphSize = ReportStyles.CodeBlock;

        // Make any raw string safe for the PDF standard fonts (strips/maps emoji etc.).
        private static string San(string? s) => ReportMarkdown.Sanitize(s);

        // -- colour bridge --
        public static PdfColor Pdf(string hex)
        {
            var (r, g, b) = ColourMath.ToRgb(hex);
            return PdfColor.FromRgb((byte)r, (byte)g, (byte)b);
        }

        // -- images --
        /// <summary>Decode a data-URL/base64 image (or resolve a bundled /reportImages/ path) into bytes OfficeIMO can draw anywhere, or null.</summary>
        public static byte[]? DecodeImage(string? dataUrl)
        {
            if (string.IsNullOrWhiteSpace(dataUrl)) return null;
            var s = dataUrl.Trim();

            // A bundled stock image referenced by the frontend path it has always used, e.g.
            // "/reportImages/board.jpg". The browser used to fetch these from public/reportImages; the
            // server ships the same files beside the assembly under reportImages/, so resolve the path to
            // those bytes. Only the file name is honoured (no traversal), and only files that ship return.
            var stock = ReportImagesPathPattern.Match(s);
            if (stock.Success) return ReportImage(stock.Groups[1].Value);

            var comma = s.IndexOf("base64,", StringComparison.OrdinalIgnoreCase);
            if (comma >= 0) s = s.Substring(comma + "base64,".Length);
            byte[] bytes;
            try { bytes = Convert.FromBase64String(s.Trim()); } catch { return null; }
            return NormaliseImage(bytes);
        }

        // Every raster OfficeIMO decodes (PNG, JPEG, GIF, BMP, TIFF, WebP) is handed to it as-is. An SVG
        // is only accepted by the drawing API, not by flow images or page backgrounds, so it is rasterised
        // once here through OfficeIMO's own SVG reader - transparent background, ~1200px on the long side,
        // crisp at logo and cover sizes and a few KB for a typical logo - and then behaves like a PNG.
        // Anything OfficeIMO cannot identify is dropped here rather than left to fail at serialisation.
        // Add-CIPPImage enforces the same list at upload time.
        private const double SvgRasterSize = 1200;
        private static byte[]? NormaliseImage(byte[] bytes)
        {
            try
            {
                if (!OfficeImageReader.TryIdentifyByContent(bytes, null, out var info)) return null;
                if (info.Format != OfficeImageFormat.Svg) return bytes;
                if (!OfficeSvgDrawingReader.TryRead(bytes, out var drawing) || drawing.Width <= 0 || drawing.Height <= 0) return null;
                return OfficeDrawingRasterRenderer.ToPng(drawing, SvgRasterSize / Math.Max(drawing.Width, drawing.Height), null);
            }
            catch { return null; }
        }

        private static readonly Regex ReportImagesPathPattern =
            new(@"(?:^|/)reportImages/([A-Za-z0-9_.\-]+\.(?:jpg|jpeg|png|gif|webp))$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        // Stock report images (cover/hero photos) ship beside the assembly under reportImages/, mirroring
        // how the twemoji PNG set and the fallback font are placed. Loaded once per file and cached.
        private static readonly Lazy<string?> ReportImageDir = new(() =>
        {
            try
            {
                var d = Path.GetDirectoryName(typeof(ReportComponents).Assembly.Location);
                if (string.IsNullOrEmpty(d)) return null;
                var dir = Path.Combine(d, "reportImages");
                return Directory.Exists(dir) ? dir : null;
            }
            catch { return null; }
        });

        private static readonly ConcurrentDictionary<string, byte[]?> ReportImageCache = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>Load a bundled stock report image by file name (no path segments), or null if it is not shipped.</summary>
        public static byte[]? ReportImage(string? fileName)
        {
            if (string.IsNullOrWhiteSpace(fileName)) return null;
            var key = Path.GetFileName(fileName); // defence in depth: strip any path
            return ReportImageCache.GetOrAdd(key, k =>
            {
                var dir = ReportImageDir.Value;
                if (dir is null) return null;
                try
                {
                    var path = Path.Combine(dir, k);
                    return File.Exists(path) ? File.ReadAllBytes(path) : null;
                }
                catch { return null; }
            });
        }

        /// <summary>
        /// The box a branding logo is drawn in: the client sets a fixed height (cover 100pt, page header
        /// 30pt) and lets the width follow the image's aspect ratio; the width cap keeps a banner-shaped
        /// logo off the cover date and out of the page-header title column.
        /// </summary>
        public static (double w, double h) LogoBox(byte[] bytes, double height, double maxWidth)
        {
            var (pxW, pxH) = ImageSize(bytes);
            var w = pxW * (height / pxH);
            if (w > maxWidth) { height *= maxWidth / w; w = maxWidth; }
            return (Math.Round(w), Math.Round(height));
        }

        /// <summary>The MIME type a drawing needs beside the bytes, from the content itself; null when OfficeIMO cannot identify it (skipped rather than failing).</summary>
        public static string? ImageContentType(byte[] b)
        {
            try { return OfficeImageReader.TryIdentifyByContent(b, null, out var info) ? info.MimeType : null; }
            catch { return null; }
        }

        /// <summary>Pixel size of any image OfficeIMO identifies (a 4:3 guess for anything it cannot).</summary>
        public static (int w, int h) ImageSize(byte[] b)
        {
            try
            {
                if (OfficeImageReader.TryIdentifyByContent(b, null, out var info) && info.Width > 0 && info.Height > 0)
                    return (info.Width, info.Height);
            }
            catch { /* fall through to the guess */ }
            return (800, 600);
        }

        // -- inline runs --
        // `size` is the base font size for the paragraph's runs (markdown has no size marks, so every run
        // in a paragraph shares it). Without an explicit size OfficeIMO falls back to its ~12pt default,
        // which is why body copy rendered far larger than the client's 9pt.
        private static void ApplyRuns(PdfParagraphBuilder b, IReadOnlyList<TextRun> runs, string bodyColour, double size)
        {
            if (runs.Count == 0) { b.Text(" "); return; }
            b.Color(Pdf(bodyColour)).FontSize(size);
            foreach (var r in runs)
            {
                // Emoji split out to inline colour images (or a monochrome glyph) so the surrounding copy
                // keeps its font/weight and an emoji never lands in a bold/italic run the fallback can't draw.
                foreach (var seg in SegmentEmoji(r.Text))
                {
                    switch (seg.Kind)
                    {
                        case EmojiSegKind.Image:
                            b.InlineImage(seg.Image!, size, size, seg.Text, OfficeImageFit.Contain, EmojiOffset(size));
                            break;
                        case EmojiSegKind.Mono:
                            b.Bold(false).Italic(false).Underline(false).Strike(false).Font(PdfStandardFont.Helvetica).Color(Pdf(seg.Tint ?? bodyColour)).Text(seg.Text);
                            break;
                        default:
                            b.Bold(r.Bold).Italic(r.Italic).Underline(r.Underline).Strike(r.Strike)
                             .Font(r.Code ? PdfStandardFont.Courier : PdfStandardFont.Helvetica).Color(Pdf(bodyColour)).Text(seg.Text);
                            break;
                    }
                }
            }
        }

        // -- primitives --
        public static void Heading(ReportContext ctx, PdfItemCompose item, int level, IReadOnlyList<TextRun> runs)
        {
            var text = RunsToPlain(runs);
            var colour = level switch { 1 => ReportColours.Ink, 2 => ctx.Theme.Palette["heading"], _ => ReportColours.Body };
            var size = level switch { 1 => ReportStyles.Heading1, 2 => ReportStyles.Heading2, _ => ReportStyles.Heading3 };
            // A markdown heading is drawn as a bold paragraph (rather than item.H1/H2/H3) so an emoji in the
            // heading renders as an inline colour image instead of a monochrome font glyph.
            item.Paragraph(b => { b.FontSize(size); EmitInline(b, text, colour, size, bold: true); },
                PdfAlign.Left, null, new PdfParagraphStyle { LineHeight = 1.15, SpacingAfter = 6 });
        }

        // The text style a run of copy is drawn with. Threaded from the enclosing component so body copy,
        // callout text and captions each render at their own size/colour/alignment - the server mirror of
        // the client's context-driven styles.
        public readonly struct TextStyle
        {
            public double Size { get; init; }
            public string Colour { get; init; }
            public PdfAlign Align { get; init; }
            public double LineHeight { get; init; }
            public double SpacingAfter { get; init; }
        }

        // Body copy: 9pt, justified. The client uses lineHeight 1.5 / 8pt after, but OfficeIMO's leading
        // renders looser at the same numbers, so a tighter 1.35 / 6pt gives the client's visual density.
        public static TextStyle BodyStyle(ReportContext ctx) => new()
        {
            Size = ReportStyles.Body, Colour = ctx.Theme.Palette["body"], Align = PdfAlign.Justify, LineHeight = 1.35, SpacingAfter = 6,
        };

        public static void Paragraph(ReportContext ctx, PdfItemCompose item, IReadOnlyList<TextRun> runs, TextStyle? style = null)
        {
            var st = style ?? BodyStyle(ctx);
            item.Paragraph(b => ApplyRuns(b, runs, st.Colour, st.Size), st.Align, null,
                new PdfParagraphStyle { LineHeight = st.LineHeight, SpacingAfter = st.SpacingAfter });
        }

        // Section title: 14pt bold heading colour (client styles.sectionTitle marginBottom 8, tightened to
        // 5 to offset OfficeIMO's looser leading around the heading).
        public static void SectionTitle(ReportContext ctx, PdfItemCompose item, string title)
            => item.Paragraph(b => { b.FontSize(ReportStyles.SectionTitle); EmitInline(b, title, ctx.Theme.Palette["heading"], ReportStyles.SectionTitle, bold: true); },
                PdfAlign.Left, null, new PdfParagraphStyle { LineHeight = 1.1, SpacingAfter = 5 });

        // A callout's list rendered as one paragraph, a line break between items (a panel ignores list
        // styling, so this matches the client's single-text-block callout bullets). `marker(i)` prefixes
        // each line (a bullet dot, or "N. " for numbered).
        private static void BulletLines(ReportContext ctx, PdfItemCompose item, IReadOnlyList<string> items, TextStyle ts, Func<int, string> marker)
        {
            if (items.Count == 0) return;
            item.Paragraph(b =>
            {
                b.FontSize(ts.Size).Color(Pdf(ts.Colour));
                for (var i = 0; i < items.Count; i++)
                {
                    if (i > 0) b.LineBreak();
                    b.Color(Pdf(ts.Colour)).Text(marker(i));
                    EmitToBuilder(b, San(items[i]), ts.Colour, ts.Size);
                }
            }, PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = ts.SpacingAfter, LineHeight = ts.LineHeight });
        }

        public static void Bullets(ReportContext ctx, PdfItemCompose item, IEnumerable<string> items, double? size = null)
            => BulletParagraphs(ctx, item, new List<string>(items), size ?? ReportStyles.BulletText, _ => "•  ");

        // A bullet/numbered list drawn as one paragraph per item (marker + emoji-aware text) rather than
        // item.Bullets, so an emoji in a list item renders as an inline colour image. Marker in the heading
        // colour; matches the old ListStyle (indent 12, 4pt item spacing, 1.3 line height).
        private static void BulletParagraphs(ReportContext ctx, PdfItemCompose item, IReadOnlyList<string> items, double size, Func<int, string> marker)
        {
            var body = ctx.Theme.Palette["body"];
            var markerColour = ctx.Theme.Palette["heading"];
            for (var i = 0; i < items.Count; i++)
            {
                var idx = i;
                item.Paragraph(b =>
                {
                    b.FontSize(size);
                    b.Bold(true).Color(Pdf(markerColour)).Text(marker(idx));
                    EmitToBuilder(b, San(items[idx]), body, size);
                }, PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = 4, LineHeight = 1.3 });
            }
        }

        public static void Numbered(ReportContext ctx, PdfItemCompose item, IEnumerable<string> items, int start, double? size = null)
            => BulletParagraphs(ctx, item, new List<string>(items), size ?? ReportStyles.BulletText, i => (start + i) + ".  ");

        // The branded cover, drawn as a page-sized OfficeDrawing over an optional full-bleed cover photo
        // (client CoverPage): date top-right, a rounded pill label chip, the two-tone title, the subtitle
        // and tenant vertically placed, and the confidential note at the bottom. A drawing lets the chip
        // be a real rounded pill and the confidential note sit at the page foot - neither is possible in
        // the plain content flow.
        public static void RenderCoverDrawing(ReportContext ctx, PdfItemCompose item)
        {
            var w = ctx.ContentWidth - 2;
            var h = ctx.ContentHeight;
            const double leftPad = 28;
            var coverText = ctx.Theme.Palette["coverText"];
            var subtitleC = ctx.Theme.Palette["subtitle"];
            var primary = ctx.Theme.Primary;
            var dw = new OfficeDrawing(w, h);

            // Vertical anchors mirror the client cover's fixed paddings (page pad 60, a header row of the
            // logo and date with a 40pt margin under it, hero paddingTop 24) rather than a proportion of
            // page height, so the block lands where the react-pdf cover puts it. The drawing origin already
            // sits at the page margin, so each client "from page top" figure is offset by PagePadding here.
            const double coverPad = 60, headerGap = 40, heroPad = 24, dateLine = 11, logoHeight = 100;
            var headerTop = coverPad - ReportStyles.PagePadding;

            // Client coverHeader: the branding logo on the left at 100pt (width by aspect ratio, capped so
            // a banner never reaches the date), the date on the right, the two vertically centred on each
            // other. Without a logo the row is just the date line, which is where the hero's 135pt top came
            // from (60 + 11 + 40 + 24).
            var logoType = ctx.Logo is { Length: > 0 } ? ImageContentType(ctx.Logo) : null;
            var logoBox = logoType is null ? (w: 0.0, h: 0.0) : LogoBox(ctx.Logo!, logoHeight, 260);
            var headerH = Math.Max(dateLine, logoBox.h);
            if (logoType is not null)
                dw.AddImage(ctx.Logo!, logoType, new OfficeImageProjection(
                    new OfficeImagePlacement(leftPad, headerTop, logoBox.w, logoBox.h), new OfficeImageSourceCrop(0, 0, 0, 0), 0, null, null, false, false));
            if (!string.IsNullOrEmpty(ctx.GeneratedOn))
                AddT(dw, San(ctx.GeneratedOn).ToUpperInvariant(), 0, headerTop + Math.Max(0, (headerH - 14) / 2), w, 14, 9, subtitleC, OfficeTextAlignment.Right);

            var coverLabel = (ctx.Variables.TryGetValue("coverlabel", out var cl) && !string.IsNullOrWhiteSpace(cl)) ? cl : "ASSESSMENT REPORT";
            coverLabel = San(coverLabel).ToUpperInvariant();
            var chipW = Math.Min(w - leftPad * 2, 26 + coverLabel.Length * 6.4);
            var y = coverPad + headerH + headerGap + heroPad - ReportStyles.PagePadding;   // client coverHero content top (chip)
            var chip = OfficeShape.RoundedRectangle(chipW, 26, 13); chip.FillColor = OC(primary);
            dw.AddShape(chip, leftPad, y);
            // AddText seats the glyph near the top of its box, so a box that merely matches the pill leaves
            // the label riding high; drop it so the 10pt label sits centred in the 26pt pill.
            AddT(dw, coverLabel, leftPad, y + 9, chipW, 12, ReportStyles.CoverLabel, ctx.Theme.OnPrimary, OfficeTextAlignment.Center, true);
            y += 58;                                  // chip height (~28) + client marginBottom 30

            // Cover title: an explicit covertitle/coveraccent override (client coverTitle/coverAccent, e.g.
            // the BEC report's "BEC Compromise" / "Analysis") else the report name split on its last word.
            string lead, accent;
            if (ctx.Variables.TryGetValue("covertitle", out var ctv) && !string.IsNullOrWhiteSpace(ctv))
            {
                lead = San(ctv).ToUpperInvariant();
                accent = (ctx.Variables.TryGetValue("coveraccent", out var cav) && !string.IsNullOrWhiteSpace(cav)) ? San(cav).ToUpperInvariant() : string.Empty;
            }
            else
            {
                var words = San(ctx.ReportName).ToUpperInvariant().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                lead = words.Length > 1 ? string.Join(" ", words[..^1]) : (words.Length == 1 ? words[0] : string.Empty);
                accent = words.Length > 1 ? words[^1] : string.Empty;
            }
            // A long line shrinks to fit rather than running off the page ("QUARTERLY SECURITY" did):
            // Helvetica Bold capitals average about 0.7em, so the size that fits is the box over that.
            double FitTitle(string s) => Math.Min(ReportStyles.CoverTitle, (w - leftPad) / Math.Max(1, s.Length * 0.7));
            var titleSize = Math.Min(FitTitle(lead), FitTitle(accent));
            if (!string.IsNullOrEmpty(lead)) { AddT(dw, lead, leftPad, y, w - leftPad, 56, titleSize, coverText, OfficeTextAlignment.Left, true); y += 53; }
            if (!string.IsNullOrEmpty(accent)) { AddT(dw, accent, leftPad, y, w - leftPad, 56, titleSize, primary, OfficeTextAlignment.Left, true); y += 53; }
            if (!string.IsNullOrEmpty(lead) || !string.IsNullOrEmpty(accent)) y += 20;  // client title marginBottom 20

            if (ctx.Variables.TryGetValue("coversubtitle", out var cs) && !string.IsNullOrWhiteSpace(cs))
            {
                // Wraps within a fixed-width box like the client subtitle (maxWidth 400); advance by the
                // wrapped height (14pt at lineHeight 1.5 ~= 21/line) plus the client subtitle marginBottom 40.
                const double subW = 400, subLine = 21;
                var subLines = Math.Max(1, Math.Ceiling(San(cs).Length / 57.0));
                AddT(dw, San(cs), leftPad, y, subW, subLine * subLines + 4, ReportStyles.CoverSubtitle, subtitleC, OfficeTextAlignment.Left, false, true);
                y += subLine * subLines + 40;
            }

            // The subject line under the title: usually the tenant, but a covertenant override names a
            // different subject (the BEC report puts the compromised user here instead of the tenant).
            var coverTenant = (ctx.Variables.TryGetValue("covertenant", out var cvt) && !string.IsNullOrWhiteSpace(cvt)) ? cvt : ctx.TenantName;
            if (!string.IsNullOrEmpty(coverTenant))
            {
                AddT(dw, San(coverTenant), leftPad, y, w - leftPad, 24, 18, coverText, OfficeTextAlignment.Left, true);
                y += 26;
            }
            // Optional cover meta (client CoverMeta): extra detail lines under the tenant, then a note.
            if (ctx.Variables.TryGetValue("covermeta", out var cm) && !string.IsNullOrWhiteSpace(cm))
                foreach (var line in cm.Replace("\r", "").Split('\n'))
                { AddT(dw, San(line), leftPad, y, w - leftPad * 2, 16, 12, subtitleC, OfficeTextAlignment.Left); y += 16; }
            if (ctx.Variables.TryGetValue("covermetanote", out var cmn) && !string.IsNullOrWhiteSpace(cmn))
                AddT(dw, San(cmn), leftPad, y + 6, w - leftPad * 2, 16, 11, subtitleC, OfficeTextAlignment.Left);

            var note = "CONFIDENTIAL & PROPRIETARY";
            if (ctx.Variables.TryGetValue("coverfooternote", out var cfn) && !string.IsNullOrWhiteSpace(cfn)) note = cfn;
            else if (!string.IsNullOrEmpty(ctx.Theme.CoverFooterText)) note = ctx.Theme.CoverFooterText;
            note = San(ReportTheme.ApplyVariables(note, ctx.Variables)).ToUpperInvariant();
            AddT(dw, note, 0, h - 16, w, 14, 9, ctx.Theme.Palette["footer"], OfficeTextAlignment.Center);

            item.Drawing(dw, PdfAlign.Left);
        }

        // Full-bleed hero content (client HeroPage overlay): the big highlight figure plus overtitle/
        // headline/subtext block, vertically centred and left-aligned, with the footer note bottom-right.
        // Drawn as one page-sized OfficeDrawing (transparent) over the section's background image, because
        // flow layout can neither vertically centre nor pin the footer to the bottom-right corner.
        public static void RenderHeroDrawing(ReportContext ctx, PdfItemCompose item, ReportNode block)
        {
            var w = ctx.ContentWidth - 2;
            var h = ctx.ContentHeight;
            var highlightColour = ctx.Theme.Palette["infographic"];
            var onDark = ctx.Theme.OnInfographic;
            var overtitle = block.Str("overtitle") ?? block.Str("heroOvertitle");
            var highlight = block.Str("highlight") ?? block.Str("heroHighlight");
            var headline = block.Str("headline") ?? block.Str("heroHeadline") ?? block.Str("title");
            var subText = block.Str("subText") ?? block.Str("heroSubText");
            var footerText = block.Str("footerText") ?? block.Str("heroFooterText");
            const double leftPad = 28, textW = 440;
            var subLines = string.IsNullOrEmpty(subText) ? Array.Empty<string>() : subText.Replace("\r", "").Split('\n');

            var blockH = (string.IsNullOrEmpty(overtitle) ? 0 : 24) + (string.IsNullOrEmpty(highlight) ? 0 : 84)
                + (string.IsNullOrEmpty(headline) ? 0 : 24) + subLines.Length * 19;
            var y = Math.Max(40, (h - blockH) / 2);

            var dw = new OfficeDrawing(w, h);
            if (!string.IsNullOrEmpty(overtitle)) { AddT(dw, San(overtitle), leftPad, y, textW, 22, 18, onDark, OfficeTextAlignment.Left, true); y += 24; }
            if (!string.IsNullOrEmpty(highlight)) { AddT(dw, San(highlight), leftPad, y, textW, 82, 72, highlightColour, OfficeTextAlignment.Left, true); y += 84; }
            if (!string.IsNullOrEmpty(headline)) { AddT(dw, San(headline), leftPad, y, textW, 22, 18, onDark, OfficeTextAlignment.Left, true); y += 24; }
            foreach (var line in subLines) { AddT(dw, San(line), leftPad, y, textW, 18, 14, onDark, OfficeTextAlignment.Left, true); y += 19; }

            if (!string.IsNullOrEmpty(footerText))
            {
                var fLines = footerText.Replace("\r", "").Split('\n');
                var fy = h - 40 - (fLines.Length - 1) * 16;
                foreach (var line in fLines) { AddT(dw, San(line), 0, fy, w - leftPad, 16, 12, onDark, OfficeTextAlignment.Right, true); fy += 16; }
            }
            item.Drawing(dw, PdfAlign.Left);
        }

        /// <summary>Rich bullets (client BulletList with {label, text}): an orange marker, a bold label, then
        /// body text - each an item.Paragraph with per-run colour so the marker and label differ from the text.</summary>
        public static void RichBullets(ReportContext ctx, PdfItemCompose item, List<object?> items)
        {
            foreach (var it in items)
            {
                var label = ReportNode.RowStr(it, "label");
                var text = ReportNode.RowStr(it, "text") ?? string.Empty;
                var marker = ReportNode.RowStr(it, "marker"); // custom marker (e.g. "1.") else a bullet dot
                item.Paragraph(b =>
                {
                    b.FontSize(ReportStyles.BulletText);
                    b.Bold(true).Color(Pdf(ctx.Theme.Palette["heading"])).Text((string.IsNullOrEmpty(marker) ? "•" : San(marker)) + "  ");
                    var body = ctx.Theme.Palette["body"];
                    if (!string.IsNullOrEmpty(label)) EmitToBuilder(b, San(label) + " ", body, ReportStyles.BulletText, bold: true);
                    EmitToBuilder(b, San(text), body, ReportStyles.BulletText, bold: false);
                }, PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = 4, LineHeight = 1.3 });
            }
        }

        /// <summary>Brand-coloured table: header band in the tenant's table colour, striped rows, repeating header.</summary>
        public static PdfTableStyle BrandedTableStyle(ReportContext ctx) => new()
        {
            HeaderFill = Pdf(ctx.Theme.Palette["table"]),
            HeaderTextColor = Pdf(ctx.Theme.OnTable),
            HeaderBold = true,
            HeaderFontSize = ReportStyles.TableHeaderCell,
            RowStripeFill = Pdf(ReportColours.Panel),
            BorderColor = Pdf(ReportColours.Line),
            BorderWidth = 0.5,
            RowSeparatorColor = Pdf(ReportColours.Line),
            RowSeparatorWidth = 0.5,
            TextColor = Pdf(ReportColours.Body),
            FontSize = ReportStyles.TableCell,
            RepeatHeaderRowCount = 1,
            CellPaddingX = 12,   // client TABLE_ROW_PADDING (horizontal cell inset)
            CellPaddingY = 6,    // client tableRow paddingVertical
        };

        // The client renders header cells uppercase (styles.tableHeaderCell textTransform), so the header
        // row (row 0) is upper-cased before it goes to OfficeIMO.
        private static List<string[]> UpperHeader(IEnumerable<string[]> rows)
        {
            var list = rows.ToList();
            if (list.Count > 0)
                list[0] = list[0].Select(c => (c ?? string.Empty).ToUpperInvariant()).ToArray();
            return list;
        }

        public static void Table(ReportContext ctx, PdfItemCompose item, IEnumerable<string[]> rows)
            => item.Table(UpperHeader(rows), PdfAlign.Left, BrandedTableStyle(ctx));

        // Shared status vocabulary (client STATUS_TONES): a status word coloured by tone.
        private static string ToneColour(string? tone) => tone switch
        {
            "pass" => ReportColours.Success,
            "warn" => ReportColours.Warning,
            "fail" => ReportColours.Danger,
            "muted" => ReportColours.Faint,
            _ => ReportColours.Body,
        };

        private static bool RowBool(object? row, string key)
            => row is Dictionary<string, object?> d && d.TryGetValue(key, out var v) && v is bool b && b;

        /// <summary>
        /// The client DataTable: column specs (header/key/width weight/bold/align) with per-cell rendering.
        /// A column with <c>toneField</c> draws its value as italic status text coloured by the row's tone
        /// field (Compliant=green, Review=red, ...); a <c>bold</c> column draws its value bold. Header band
        /// in the brand table colour, uppercase; striped body rows; rows beyond <c>limit</c> drop to a note.
        /// </summary>
        public static void RichTable(ReportContext ctx, PdfItemCompose item, List<object?> columns, List<object?> rows, int limit)
        {
            if (columns.Count == 0) return;
            var widths = new List<double>();
            var aligns = new List<PdfColumnAlign>();
            var header = new List<PdfTableCell>();
            foreach (var c in columns)
            {
                var w = ReportNode.RowNum(c, "width"); if (w <= 0) w = 1;
                widths.Add(w);
                aligns.Add((ReportNode.RowStr(c, "align")) switch { "center" => PdfColumnAlign.Center, "right" => PdfColumnAlign.Right, _ => PdfColumnAlign.Left });
                // Header runs (not a plain string) so an emoji in a column header renders as a colour image;
                // the brand header fill/uppercase come from the table style, the text colour is OnTable bold.
                header.Add(CellRuns((ReportNode.RowStr(c, "header") ?? string.Empty).ToUpperInvariant(), ctx.Theme.OnTable, bold: true, size: ReportStyles.TableHeaderCell));
            }

            var shown = limit > 0 ? rows.Take(limit).ToList() : rows;
            var hidden = rows.Count - (limit > 0 ? Math.Min(limit, rows.Count) : rows.Count);
            var cells = new List<PdfTableCell[]> { header.ToArray() };
            foreach (var r in shown)
            {
                var rowCells = new PdfTableCell[columns.Count];
                for (var ci = 0; ci < columns.Count; ci++)
                {
                    var col = columns[ci];
                    var key = ReportNode.RowStr(col, "key") ?? string.Empty;
                    var text = San(ReportNode.RowStr(r, key) ?? string.Empty);
                    var toneField = ReportNode.RowStr(col, "toneField");
                    var colourField = ReportNode.RowStr(col, "colourField");
                    if (!string.IsNullOrEmpty(toneField))
                    {
                        var colour = ToneColour(ReportNode.RowStr(r, toneField));
                        rowCells[ci] = CellRuns(text, colour, bold: false, italic: true);
                    }
                    else if (!string.IsNullOrEmpty(colourField))
                    {
                        // Bold text in an arbitrary per-row colour (client column.colour(row), e.g. risk bands).
                        var colour = ReportNode.RowStr(r, colourField);
                        rowCells[ci] = CellRuns(text, string.IsNullOrEmpty(colour) ? ReportColours.Body : colour, bold: true);
                    }
                    else if (RowBool(col, "bold"))
                    {
                        rowCells[ci] = CellRuns(text, ReportColours.Body, bold: true);
                    }
                    else
                    {
                        rowCells[ci] = CellRuns(text, ReportColours.Body);
                    }
                }
                cells.Add(rowCells);
            }

            var style = BrandedTableStyle(ctx);
            style.ColumnWidthWeights = widths;
            style.Alignments = aligns;
            item.Table(cells, PdfAlign.Left, style);
            if (hidden > 0)
                Note(ctx, item, $"... and {hidden} more. Export the table from the report page for the full list.");
        }

        public static void Code(ReportContext ctx, PdfItemCompose item, string text)
            => item.Paragraph(b =>
            {
                b.Font(PdfStandardFont.Courier).FontSize(CodeParagraphSize).Color(Pdf(ReportColours.Body));
                var lines = San(text).Replace("\r\n", "\n").Split('\n');
                for (var i = 0; i < lines.Length; i++) { if (i > 0) b.LineBreak(); b.Text(lines[i]); }
            });

        public static void Hr(ReportContext ctx, PdfItemCompose item) => item.HR();

        // A small italic aside after a truncated list (client styles.truncationNote): 8pt faint italic,
        // indented to the table's inner padding.
        public static void Note(ReportContext ctx, PdfItemCompose item, string text)
            => item.Paragraph(b => { b.Italic(true).FontSize(ReportStyles.TableCell); EmitInline(b, text, ReportColours.Faint, ReportStyles.TableCell); },
                PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, SpacingAfter = 4 });

        // -- callouts (InfoBox / AlertBox / ClearBox) --
        // Callouts are drawn as a single-cell bordered TABLE, not a Panel: OfficeIMO panels apply a fixed
        // internal paragraph leading and ignore per-call line-height/spacing, which opens a loose gap
        // between the title and body and between body lines. A table cell honours run sizing and cell
        // padding exactly (the same reason StatCard is a cell), so the callout matches the client's tight
        // spacing. The title is a bold run, then a small line-break run sets the title/body gap, then the
        // body runs; a left accent stripe is a per-cell LeftBorder over the cell's full border.
        private const double CalloutPadX = 12;      // client infoBox/alertBox padding (horizontal)
        private const double CalloutPadY = 12;      // fallback vertical cell padding
        private const double CalloutPadTop = 11;    // top padding (client padding 12, less the cell's own top leading)
        private const double CalloutPadBottom = 10; // bottom padding (client 12; the cell's line descent already adds space)
        private const double CalloutGap = 12;    // space after an InfoBox/ClearBox (client infoBox marginBottom 12)
        private const double AlertGap = 16;      // space after an AlertBox (client alertBox marginBottom 16)
        private const double SectionGap = 12;    // space before a new section's heading (client section marginBottom 12)

        private static PdfTextRun Run(string text, string colour, double size, bool bold = false, bool italic = false, bool underline = false, bool strike = false)
            => new(San(text), bold, underline, Pdf(colour), italic, strike, size);

        // The brand tint for the three report emoji when they fall back to the monochrome font (no colour
        // image bundled); every other emoji renders untinted. Null for anything that is not a report emoji.
        public static string? EmojiTint(int cp) =>
            cp == ReportMarkdown.EmojiWarning ? "#DD9B26" :   // amber
            cp == ReportMarkdown.EmojiCheck ? "#2F9E44" :     // green
            cp == ReportMarkdown.EmojiInfo ? "#3182CE" :      // blue
            null;

        // An emoji renders at the run's font size, dropped a touch below the baseline so it sits like a glyph.
        private const double EmojiBaselineFactor = -0.12;
        private static double EmojiOffset(double size) => size * EmojiBaselineFactor;

        private enum EmojiSegKind { Text, Image, Mono }
        private readonly struct EmojiSegment
        {
            public EmojiSegKind Kind { get; init; }
            public string Text { get; init; }    // Text: the copy; Image: alt text; Mono: the glyph
            public byte[]? Image { get; init; }   // Image: the colour PNG bytes
            public string? Tint { get; init; }    // Mono: brand tint hex, or null
        }

        // Split (already-sanitized) text into text / colour-image / monochrome-glyph segments. An emoji
        // grapheme cluster (including a multi-code-point ZWJ sequence, flag or skin-tone) routes to a bundled
        // Twemoji colour image when one exists, else to the monochrome fallback font (tinted for the three
        // report emoji); everything else stays as text, so ordinary copy is untouched.
        private static IEnumerable<EmojiSegment> SegmentEmoji(string text)
        {
            var list = new List<EmojiSegment>();
            var sb = new System.Text.StringBuilder();
            void FlushText() { if (sb.Length > 0) { list.Add(new EmojiSegment { Kind = EmojiSegKind.Text, Text = sb.ToString() }); sb.Clear(); } }
            var e = System.Globalization.StringInfo.GetTextElementEnumerator(text);
            while (e.MoveNext())
            {
                var cluster = (string)e.Current;
                if (cluster.Length == 1 && cluster[0] <= 'ÿ') { sb.Append(cluster); continue; }
                var bytes = TwemojiAssets.Enabled ? TwemojiAssets.Bytes(cluster) : null;
                if (bytes is not null) { FlushText(); list.Add(new EmojiSegment { Kind = EmojiSegKind.Image, Image = bytes, Text = cluster }); continue; }
                if (cluster.Length <= 2 && ReportMarkdown.RenderEmojiGlyphs)
                {
                    var cp = char.ConvertToUtf32(cluster, 0);
                    if (ReportMarkdown.EmojiCoverage.Contains(cp) || EmojiTint(cp) is not null)
                    { FlushText(); list.Add(new EmojiSegment { Kind = EmojiSegKind.Mono, Text = cluster, Tint = EmojiTint(cp) }); continue; }
                }
                sb.Append(cluster);
            }
            FlushText();
            return list;
        }

        // Emit text as OfficeIMO runs for table-cell content (callouts): each emoji becomes an inline colour-
        // image run (or a monochrome glyph run when no image is bundled), the rest keeps the given colour and
        // marks. A monochrome glyph carries no weight or decoration of its own, so it is emitted plain.
        private static void EmitRuns(List<PdfTextRun> dest, string text, string colour, double size,
            bool bold = false, bool italic = false, bool underline = false, bool strike = false,
            double? emojiSize = null, double? emojiOffset = null)
        {
            // An emoji image defaults to the run's font size, but a caller can shrink it and set its baseline
            // offset (the stat card's big number sizes the emoji to ~the digit height and drops it onto the
            // number's cap box, so it doesn't raise the line's ascent and push the number below a sibling card
            // whose number has no emoji).
            var es = emojiSize ?? size;
            var eo = emojiOffset ?? EmojiOffset(es);
            foreach (var seg in SegmentEmoji(San(text)))
            {
                switch (seg.Kind)
                {
                    case EmojiSegKind.Image:
                        dest.Add(PdfTextRun.Inline(new PdfInlineImage(seg.Image!, es, es, seg.Text, OfficeImageFit.Contain, eo)));
                        break;
                    case EmojiSegKind.Mono:
                        dest.Add(new PdfTextRun(seg.Text, false, false, Pdf(seg.Tint ?? colour), false, false, size));
                        break;
                    default:
                        dest.Add(new PdfTextRun(seg.Text, bold, underline, Pdf(colour), italic, strike, size));
                        break;
                }
            }
        }

        // A table cell whose text renders emoji as inline colour images (via EmitRuns) at the given colour
        // and weight, so a body cell like "ok ✅" shows a colour glyph rather than a monochrome one.
        private static PdfTableCell CellRuns(string text, string colour, bool bold = false, bool italic = false, double? size = null)
        {
            var runs = new List<PdfTextRun>();
            EmitRuns(runs, text, colour, size ?? ReportStyles.TableCell, bold, italic);
            return new PdfTableCell(runs);
        }

        // Emit inline text (with colour-image emoji) into a paragraph builder. For callers that compose on a
        // builder outside the component kit - the page header title/subtitle in ReportPdf.
        public static void EmitInline(PdfParagraphBuilder b, string text, string colour, double size, bool bold = false)
            => EmitToBuilder(b, San(text), colour, size, bold);

        // Convert parsed inline runs to OfficeIMO runs at a callout's size/colour, marks carried through,
        // with kept emoji split into their own tinted runs.
        private static IEnumerable<PdfTextRun> ToPdfRuns(IEnumerable<TextRun> runs, string colour, double size)
        {
            var dest = new List<PdfTextRun>();
            foreach (var r in runs) EmitRuns(dest, r.Text, colour, size, r.Bold, r.Italic, r.Underline, r.Strike);
            return dest;
        }

        // A callout body flattened to one run list: each logical line separated by a line-break run, so the
        // cell renders it as tight consecutive lines. `lines` keeps the source '\n' splits (label/value
        // detail lists); otherwise the markdown blocks are flattened (paragraphs, and bullets as "- " lines).
        private static List<PdfTextRun> CalloutBodyRuns(ReportContext ctx, string content, bool lines, double size, string colour)
        {
            var outRuns = new List<PdfTextRun>();
            void AddLine(IEnumerable<PdfTextRun> lineRuns)
            {
                if (outRuns.Count > 0) outRuns.Add(Run("\n", colour, size));
                outRuns.AddRange(lineRuns);
            }
            if (lines)
            {
                foreach (var ln in San(content).Replace("\r\n", "\n").Split('\n'))
                    AddLine(ToPdfRuns(ReportMarkdown.MarkdownRuns(ln), colour, size));
            }
            else
            {
                foreach (var node in ReportMarkdown.MarkdownToNodes(content))
                {
                    switch (node.Type)
                    {
                        case "paragraph":
                            AddLine(ToPdfRuns(node.Get<List<TextRun>>("runs") ?? new List<TextRun>(), colour, size));
                            break;
                        case "bullets":
                            foreach (var s in StringItems(node)) AddLine(new[] { Run("•  " + s, colour, size) });
                            break;
                        case "numbered":
                            var n = (int)(node.Num("start") ?? 1);
                            foreach (var s in StringItems(node)) AddLine(new[] { Run($"{n++}.  " + s, colour, size) });
                            break;
                        default:
                            var t = node.Str("content") ?? node.Str("text");
                            if (!string.IsNullOrEmpty(t)) AddLine(ToPdfRuns(ReportMarkdown.MarkdownRuns(t), colour, size));
                            break;
                    }
                }
            }
            if (outRuns.Count == 0) outRuns.Add(Run(" ", colour, size));
            return outRuns;
        }

        // The callout as stacked table rows: a title row (with its own bottom margin) over a body row (with
        // a tight body line height), or a single body row when untitled. One bordered cell stack lets the
        // title/body gap and the body line spacing each be set exactly - a single cell forces one uniform
        // line advance (the title can't get its own margin), and a panel's leading can't be set at all.
        private static List<PdfTableCell[]> CalloutRows(string? title, string titleColour, double titleSize, List<PdfTextRun> bodyRuns)
        {
            // One cell, one row: a multi-row table always draws a divider between rows (OfficeIMO borders are
            // a grid), so title and body live in the same cell. The title is a bold run then a body-size line
            // break; the cell's natural leading (no LineHeight override) then gives the taller title line its
            // own margin above the body - matching the client's infoTitle marginBottom - while the body lines
            // sit at the client's ~1.4 leading. This is why the callout uses no LineHeight.
            var runs = new List<PdfTextRun>();
            if (!string.IsNullOrEmpty(title))
            {
                EmitRuns(runs, title!, titleColour, titleSize, bold: true);
                runs.Add(Run("\n", titleColour, ReportStyles.InfoText));
            }
            runs.AddRange(bodyRuns);
            return new List<PdfTableCell[]> { new[] { new PdfTableCell(runs) } };
        }

        private static PdfTableStyle CalloutStyle(string bgHex, string? stripeHex, double stripeWidth, string borderHex, double borderWidth)
        {
            // Single cell -> the table's BorderWidth draws just the perimeter box (no interior grid). The left
            // edge is overridden with the accent stripe via a per-cell LeftBorder when the callout has one.
            var style = new PdfTableStyle
            {
                HeaderRowCount = 0,
                BorderColor = Pdf(borderHex),
                BorderWidth = borderWidth,
                RowSeparatorWidth = 0,
                CellPaddingX = CalloutPadX,
                CellPaddingY = CalloutPadY,
                CellPaddings = new Dictionary<(int, int), PdfCellPadding>
                {
                    [(0, 0)] = new PdfCellPadding { Left = CalloutPadX, Right = CalloutPadX, Top = CalloutPadTop, Bottom = CalloutPadBottom },
                },
                SpacingAfter = 0,                 // the gap after a callout is an explicit Spacer, not the table's
                KeepTogether = true,              // a callout never splits across a page (client keeps each whole)
                CellFills = new Dictionary<(int, int), PdfColor> { [(0, 0)] = Pdf(bgHex) },
            };
            if (stripeHex is not null)
                style.CellBorders = new Dictionary<(int, int), PdfCellBorder>
                {
                    [(0, 0)] = new PdfCellBorder { LeftBorder = new PdfCellBorderSide { Color = Pdf(stripeHex), Width = stripeWidth } },
                };
            return style;
        }

        /// <summary>
        /// A titled note with an accent stripe down its left edge (client InfoBox). `tone` (ok/warn) tints
        /// the background and title; `colour` recolours the stripe (and the title when tintTitle). `content`
        /// is markdown, or line-broken label/value text when `lines`.
        /// </summary>
        public static void InfoBox(ReportContext ctx, PdfItemCompose item, string? title, string? tone,
            string? colour, bool tintTitle, string content, bool lines = false)
        {
            var (accent, bg, titleColour) = InfoBoxColours(ctx, tone, colour, tintTitle);
            var body = CalloutBodyRuns(ctx, content, lines, ReportStyles.InfoText, ctx.Theme.Palette["subtitle"]);
            item.Table(CalloutRows(title, titleColour, ReportStyles.InfoTitle, body), PdfAlign.Left, CalloutStyle(bg, accent, 4, ReportColours.Line, 1));
            item.Spacer(CalloutGap);
        }

        // An InfoBox's stripe accent, background tint and title colour: `tone` (ok/warn) picks the tint,
        // `colour` overrides the stripe (and the title when tintTitle).
        private static (string accent, string bg, string title) InfoBoxColours(ReportContext ctx, string? tone, string? colour, bool tintTitle)
        {
            var accent = string.IsNullOrEmpty(colour) ? ctx.Theme.Palette["card"] : colour!;
            var (bg, title) = tone switch
            {
                "ok" => (ReportColours.OkBg, ReportColours.Success),
                "warn" => (ReportColours.WarnBg, ReportColours.Warning),
                _ => (ReportColours.Panel, ctx.Theme.Palette["body"]),
            };
            if (tintTitle && !string.IsNullOrEmpty(colour)) title = colour!;
            return (accent, bg, title);
        }

        /// <summary>A warning callout: red-tinted background with a full accent-coloured border (client AlertBox).</summary>
        public static void AlertBox(ReportContext ctx, PdfItemCompose item, string? title, string? colour, string content, bool lines = false)
        {
            var accent = string.IsNullOrEmpty(colour) ? ctx.Theme.Palette["card"] : colour!;
            var body = CalloutBodyRuns(ctx, content, lines, ReportStyles.AlertText, ctx.Theme.Palette["body"]);
            item.Table(CalloutRows(title, accent, ReportStyles.AlertTitle, body), PdfAlign.Left, CalloutStyle(ReportColours.AlertBg, null, 0, accent, 2));
            item.Spacer(AlertGap);
        }

        /// <summary>The all-clear counterpart to AlertBox - a green InfoBox for a check that found nothing.</summary>
        public static void ClearBox(ReportContext ctx, PdfItemCompose item, string? title, string content, bool lines = false)
            => InfoBox(ctx, item, title, "ok", null, false, content, lines);

        // Body copy stepped in under a heading (client Paragraph indent: marginLeft 12, marginTop 8). Used
        // for the BEC summary lines that introduce a check's detail callouts.
        public static void IndentedParagraph(ReportContext ctx, PdfItemCompose item, string text)
        {
            item.Spacer(4);
            var body = ctx.Theme.Palette["body"];
            item.Paragraph(b => { b.FontSize(ReportStyles.Body); EmitToBuilder(b, San(text), body, ReportStyles.Body); },
                PdfAlign.Left, null, new PdfParagraphStyle { LeftIndent = 12, LineHeight = 1.3, SpacingAfter = 0 });
        }

        // Write text into a paragraph builder: emoji as inline colour images (or a monochrome glyph), the
        // rest as coloured text - the paragraph equivalent of EmitRuns, for contexts that compose directly
        // on a PdfParagraphBuilder.
        private static void EmitToBuilder(PdfParagraphBuilder b, string text, string colour, double size, bool bold = false)
        {
            foreach (var seg in SegmentEmoji(text))
            {
                switch (seg.Kind)
                {
                    case EmojiSegKind.Image:
                        b.InlineImage(seg.Image!, size, size, seg.Text, OfficeImageFit.Contain, EmojiOffset(size));
                        break;
                    case EmojiSegKind.Mono:
                        b.Bold(false).Color(Pdf(seg.Tint ?? colour)).Text(seg.Text);
                        break;
                    default:
                        b.Bold(bold).Color(Pdf(colour)).Text(seg.Text);
                        break;
                }
            }
        }

        /// <summary>
        /// A grid of InfoBoxes laid out `cols` per row (client `Columns` of callouts, e.g. the Shadow AI
        /// risk-level pairs). Each item is a node with title/content/tone/colour/tintTitle. Short final rows
        /// are padded so columns keep their width.
        /// </summary>
        public static void InfoBoxColumns(ReportContext ctx, PdfItemCompose item, List<object?> items, int cols)
        {
            if (items.Count == 0) return;
            if (cols < 1) cols = 1;
            var width = 100.0 / cols;
            for (var start = 0; start < items.Count; start += cols)
            {
                var slice = items.Skip(start).Take(cols).ToList();
                item.Row(r =>
                {
                    r.Gap(10);
                    foreach (var node in slice)
                        r.Column(width, col => InfoBoxCol(ctx, col,
                            ReportNode.RowStr(node, "title"), ReportNode.RowStr(node, "tone"),
                            ReportNode.RowStr(node, "colour"), RowBool(node, "tintTitle"),
                            ReportNode.RowStr(node, "content") ?? string.Empty));
                    for (var k = slice.Count; k < cols; k++) r.Column(width, _ => { });
                });
                item.Spacer(CalloutGap);
            }
        }

        // One InfoBox rendered inside a row column, as the same single-cell table used full width.
        private static void InfoBoxCol(ReportContext ctx, PdfRowColumnCompose col, string? title, string? tone,
            string? colour, bool tintTitle, string content)
        {
            var (accent, bg, titleColour) = InfoBoxColours(ctx, tone, colour, tintTitle);
            var body = CalloutBodyRuns(ctx, content, false, ReportStyles.InfoText, ctx.Theme.Palette["subtitle"]);
            col.Table(CalloutRows(title, titleColour, ReportStyles.InfoTitle, body), PdfAlign.Left, CalloutStyle(bg, accent, 4, ReportColours.Line, 1));
        }

        // Series colour for a chart entry: its own colour, else the theme series cycled by index.
        private static string SeriesColour(ReportContext ctx, string? own, int index)
        {
            if (!string.IsNullOrEmpty(own)) return own;
            var s = ctx.Theme.Series;
            return s.Count > 0 ? s[index % s.Count] : ctx.Theme.Palette["chart"];
        }

        // A row of stat cards. Each card is a single-column table inside its own row column, because a
        // panel inside a row column left-aligns its text regardless of alignment, whereas a table cell
        // honours Alignments.Center - so the number and label sit centred like the client statCard. The
        // gaps between cards come from the row gap; the brand accent is the card's top border.
        public static void StatRow(ReportContext ctx, PdfItemCompose item, List<object?> stats)
        {
            if (stats.Count == 0) return;
            var accent = ctx.Theme.Palette["card"];
            var width = 100.0 / stats.Count; // column widths are percentages and must sum to ~100
            // Each card is its own single-cell table, so a caption on one card makes only that card taller
            // and its border box no longer lines up with the rest. When any card in the row has a caption,
            // every other card reserves a blank caption line so all the boxes stay the same height.
            var reserveCaption = stats.Any(s => !string.IsNullOrEmpty(ReportNode.RowStr(s, "caption")));
            item.Row(r =>
            {
                r.Gap(10);
                foreach (var s in stats)
                {
                    var value = ReportNode.RowStr(s, "value") ?? string.Empty;
                    var label = (ReportNode.RowStr(s, "label") ?? string.Empty).ToUpperInvariant();
                    var caption = ReportNode.RowStr(s, "caption");
                    var colour = ReportNode.RowStr(s, "colour") ?? accent;
                    r.Column(width, col => StatCard(ctx, col, value, label, caption, colour, accent, reserveCaption));
                }
            });
            item.Spacer(8);
        }

        private static void StatCard(ReportContext ctx, PdfRowColumnCompose col, string value, string label, string? caption, string colour, string accent, bool reserveCaption = false)
        {
            // One cell, the number over the label as separate runs split by a line break, so there is no
            // internal row divider - just the outer card border and its brand top accent.
            var runs = new List<PdfTextRun>();
            // Size a number-adjacent emoji to ~the digit height and seat it on the digit cap box, so it does
            // not raise the line's ascent - otherwise the number rides lower than a sibling card with no emoji
            // (proportions measured for alignment: emoji ~0.55x the number, dropped ~0.18x onto the baseline).
            EmitRuns(runs, value, colour, ReportStyles.StatNumber, bold: true,
                emojiSize: ReportStyles.StatNumber * 0.55, emojiOffset: ReportStyles.StatNumber * -0.18);
            runs.Add(Run("\n", colour, ReportStyles.StatNumber));
            EmitRuns(runs, label, ReportColours.Muted, ReportStyles.StatLabel, bold: true);
            if (!string.IsNullOrEmpty(caption))
            {
                runs.Add(Run("\n", ctx.Theme.Palette["subtitle"], ReportStyles.StatCaption));
                EmitRuns(runs, caption!, ctx.Theme.Palette["subtitle"], ReportStyles.StatCaption);
            }
            else if (reserveCaption)
            {
                // A blank caption line so this card matches the height of captioned cards in the same row.
                runs.Add(Run("\n", ctx.Theme.Palette["subtitle"], ReportStyles.StatCaption));
                runs.Add(Run(" ", ctx.Theme.Palette["subtitle"], ReportStyles.StatCaption));
            }
            var rows = new List<PdfTableCell[]> { new[] { new PdfTableCell(runs) } };
            var style = new PdfTableStyle
            {
                HeaderRowCount = 0,
                BorderColor = Pdf(ReportColours.Line),
                BorderWidth = 1,
                RowSeparatorWidth = 0,
                CellPaddingX = 6,
                CellPaddingY = 8,
                // The big number needs clear space under the top accent (a plain number otherwise sits tight
                // against it), balanced by a comfortable bottom pad under the caption.
                CellPaddings = new Dictionary<(int, int), PdfCellPadding>
                {
                    [(0, 0)] = new PdfCellPadding { Left = 6, Right = 6, Top = 22, Bottom = 12 },
                },
                Alignments = new List<PdfColumnAlign> { PdfColumnAlign.Center },
                CellFills = new Dictionary<(int, int), PdfColor> { [(0, 0)] = Pdf(ReportColours.White) },
                CellBorders = new Dictionary<(int, int), PdfCellBorder>
                {
                    [(0, 0)] = new PdfCellBorder { TopBorder = new PdfCellBorderSide { Color = Pdf(accent), Width = 3 } },
                },
            };
            col.Table(rows, PdfAlign.Left, style);
        }

        // Labelled progress bars (client ProgressList): each item is its own bordered row box holding a
        // bold label, a data bar over a grey track, and a bold value. One 1-row table per item gives the
        // per-row border and lets the label/value be bold via cell runs; the row gap comes from a spacer.
        public static void Progress(ReportContext ctx, PdfItemCompose item, List<object?> items)
        {
            if (items.Count == 0) return;
            for (var i = 0; i < items.Count; i++)
            {
                var it = items[i];
                var label = ReportNode.RowStr(it, "label") ?? string.Empty;
                var value = ReportNode.RowNum(it, "value");
                var max = ReportNode.RowNum(it, "max"); if (max <= 0) max = 100;
                var pct = Math.Max(0, Math.Min(1, value / max));
                var display = ReportNode.RowStr(it, "display");
                if (string.IsNullOrEmpty(display)) display = Math.Round(pct * 100) + "%";
                var colour = ReportNode.RowStr(it, "colour") ?? SeriesColour(ctx, null, i);
                var rows = new List<PdfTableCell[]>
                {
                    new[]
                    {
                        CellRuns(label, ctx.Theme.Palette["body"], bold: true),
                        new PdfTableCell(string.Empty),
                        CellRuns(display!, ReportColours.Body, bold: true),
                    },
                };
                var style = new PdfTableStyle
                {
                    HeaderRowCount = 0,
                    BorderColor = Pdf(ReportColours.Line),
                    BorderWidth = 1,
                    RowSeparatorWidth = 0,
                    CellPaddingX = 10,
                    CellPaddingY = 7,
                    ColumnWidthWeights = new List<double> { 28, 58, 14 },
                    Alignments = new List<PdfColumnAlign> { PdfColumnAlign.Left, PdfColumnAlign.Left, PdfColumnAlign.Right },
                    VerticalAlignments = new List<PdfCellVerticalAlign> { PdfCellVerticalAlign.Middle, PdfCellVerticalAlign.Middle, PdfCellVerticalAlign.Middle },
                    CellFills = new Dictionary<(int, int), PdfColor> { [(0, 1)] = Pdf(ReportColours.Line) },
                    CellDataBars = new Dictionary<(int, int), PdfCellDataBar> { [(0, 1)] = new PdfCellDataBar { Color = Pdf(colour), Ratio = pct, StartRatio = 0 } },
                };
                item.Table(rows, PdfAlign.Left, style);
                item.Spacer(6);
            }
        }

        // -- charts (vector) --
        // Real vector charts, ported 1:1 from the client charts.jsx which draws SVG into a 400x200 viewBox.
        // Built as an OfficeDrawing (a fixed-size composite that flows as one block and reserves its
        // height - unlike item.Canvas, which paints page-absolute and lets neighbours overlap it). The
        // drawing shares the SVG coordinate system (top-left origin, y down), so the geometry is copied
        // verbatim: the 400x200 plot is centred in a bordered white frame, title above, caption below.
        private const double ChartViewW = 400, ChartViewH = 200;
        private const double ChartTitleSize = 10, ChartLabelSize = 7;

        private static OfficeColor OC(string hex)
        {
            var (r, g, b) = ColourMath.ToRgb(hex);
            return OfficeColor.FromRgb((byte)r, (byte)g, (byte)b);
        }

        private static string FmtNum(double v)
            => v == Math.Floor(v) ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("0.##", CultureInfo.InvariantCulture);

        // Positioned text into an OfficeDrawing at an explicit size/colour/alignment (AddText takes the
        // size via the font, so every label supplies a Helvetica OfficeFontInfo).
        private static void AddT(OfficeDrawing dw, string text, double x, double y, double w, double h,
            double size, string colourHex, OfficeTextAlignment align, bool bold = false, bool wrap = false)
            // The extended overload's wrapText makes a long block (the cover subtitle) fold inside its box
            // instead of overrunning the page; the short overload leaves WrapText off (read-only afterwards).
            => dw.AddText(text, x, y, w, h,
                new OfficeFontInfo("Helvetica", size, bold ? OfficeFontStyle.Bold : OfficeFontStyle.Regular),
                OC(colourHex), align, lineHeight: null, wrapText: wrap);

        public static void Chart(ReportContext ctx, PdfItemCompose item, string? kind, List<object?> data,
            string? title = null, string? caption = null, double? max = null, string? centreLabel = null)
        {
            var k = (kind ?? "bar").ToLowerInvariant();
            var w = ctx.ContentWidth - 2; // a drawing exactly the content width is rejected as too wide
            const double pad = 16, titleH = 14, titleGap = 12, captionGap = 8, captionH = 10;
            var hasTitle = !string.IsNullOrEmpty(title);
            var hasCaption = !string.IsNullOrEmpty(caption);
            var plotTop = pad + (hasTitle ? titleH + titleGap : 0);
            var leftPad = Math.Max(0, (w - ChartViewW) / 2);
            var totalH = plotTop + ChartViewH + pad + (hasCaption ? captionGap + captionH : 0);

            var dw = new OfficeDrawing(w, totalH);
            var frame = OfficeShape.RoundedRectangle(w, totalH, 6);
            frame.FillColor = OC(ReportColours.White); frame.StrokeColor = OC(ReportColours.Line); frame.StrokeWidth = 1;
            dw.AddShape(frame, 0, 0);
            if (hasTitle)
                AddT(dw, San(title!), 0, pad, w, titleH, ChartTitleSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Center, true);

            var entries = data.Select((d, i) => (
                label: ReportNode.RowStr(d, "label") ?? string.Empty,
                value: ReportNode.RowNum(d, "value"),
                colour: SeriesColour(ctx, ReportNode.RowStr(d, "colour"), i))).ToList();

            if (entries.Count == 0)
                AddT(dw, "No data available for this chart.", 0, plotTop + ChartViewH / 2 - 6, w, 12, ReportStyles.Body, ReportColours.Faint, OfficeTextAlignment.Center);
            else if (k == "donut") DrawDonut(ctx, dw, entries, leftPad, plotTop, centreLabel);
            else if (k == "trend") DrawTrend(ctx, dw, entries, leftPad, plotTop, max);
            else DrawBar(ctx, dw, entries, leftPad, plotTop);

            if (hasCaption)
                AddT(dw, San(caption!), 0, plotTop + ChartViewH + captionGap, w, captionH, ChartLabelSize, ctx.Theme.Palette["chart"], OfficeTextAlignment.Center);

            item.Drawing(dw, PdfAlign.Left);
            item.Spacer(12);
        }

        private static (double x, double y) Polar(double cx, double cy, double r, double deg)
            => (cx + r * Math.Cos(deg * Math.PI / 180), cy + r * Math.Sin(deg * Math.PI / 180));

        // Append cubic-bezier segments approximating a circular arc from a0 to a1 (radians) at radius r.
        // Assumes the current path point is already at a0. Handles either sweep direction via the sign of
        // (a1 - a0), splitting into <=90 degree segments (the standard 4/3*tan(dθ/4) control-point method).
        private static void ArcBeziers(List<OfficePathCommand> cmds, double cx, double cy, double r, double a0, double a1)
        {
            var segs = Math.Max(1, (int)Math.Ceiling(Math.Abs(a1 - a0) / (Math.PI / 2)));
            var d = (a1 - a0) / segs;
            var t = a0;
            for (var s = 0; s < segs; s++)
            {
                var t2 = t + d;
                var k = 4.0 / 3.0 * Math.Tan(d / 4);
                var x0 = cx + r * Math.Cos(t); var y0 = cy + r * Math.Sin(t);
                var x3 = cx + r * Math.Cos(t2); var y3 = cy + r * Math.Sin(t2);
                var c1x = x0 - k * r * Math.Sin(t); var c1y = y0 + k * r * Math.Cos(t);
                var c2x = x3 + k * r * Math.Sin(t2); var c2y = y3 - k * r * Math.Cos(t2);
                cmds.Add(OfficePathCommand.CubicBezierTo(c1x, c1y, c2x, c2y, x3, y3));
                t = t2;
            }
        }

        private static void DrawBar(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy)
        {
            const double plotLeft = 40, plotTop = 20, plotWidth = 340, plotHeight = 130;
            const double plotBottom = plotTop + plotHeight;
            var maxValue = Math.Max(entries.Max(e => e.value), 0); if (maxValue <= 0) maxValue = 1;
            var slot = plotWidth / entries.Count;
            var barWidth = Math.Min(slot * 0.6, 46);

            // Lines are placed at their start point with endpoints relative to it (a shape's coordinates
            // are normalised to its own box, so absolute endpoints would collapse to the origin).
            var axis = OfficeShape.Line(0, 0, plotWidth, 0);
            axis.StrokeColor = OC(ReportColours.Line); axis.StrokeWidth = 1; dw.AddShape(axis, ox + plotLeft, oy + plotBottom);

            for (var i = 0; i < entries.Count; i++)
            {
                var e = entries[i];
                var height = Math.Max(e.value / maxValue * plotHeight, e.value > 0 ? 2 : 1);
                var x = plotLeft + i * slot + (slot - barWidth) / 2;
                var y = plotBottom - height;
                var bar = OfficeShape.RoundedRectangle(barWidth, height, 2);
                bar.FillColor = OC(e.colour); dw.AddShape(bar, ox + x, oy + y);
                AddT(dw, FmtNum(e.value), ox + plotLeft + i * slot, oy + y - 11, slot, 9, ChartLabelSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Center);
                var label = e.label.Length > 14 ? e.label.Substring(0, 13) + "…" : e.label;
                AddT(dw, San(label), ox + plotLeft + i * slot, oy + plotBottom + 5, slot, 9, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Center);
            }
        }

        private static void DrawDonut(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, string? centreLabel = null)
        {
            var visible = entries.Where(e => e.value > 0).ToList();
            var total = visible.Sum(e => e.value);
            if (total <= 0)
            {
                AddT(dw, "No data available for this chart.", ox, oy + ChartViewH / 2 - 6, ChartViewW, 12, ReportStyles.Body, ReportColours.Faint, OfficeTextAlignment.Center);
                return;
            }
            // Local chart coords (0..400, 0..200); all slices share one 400x200 path box placed at the
            // chart offset, so they align (a bare Path() normalises each to its own box and misplaces them).
            double cx = ChartViewW / 2, cy = 85, outerR = 60, innerR = 25;
            double preceding = 0;
            foreach (var e in visible)
            {
                var startAngle = -90 + preceding / total * 360;
                var angle = Math.Min(e.value / total * 360, 359.99);
                var endAngle = startAngle + angle;
                var os = Polar(cx, cy, outerR, startAngle);
                var ie = Polar(cx, cy, innerR, endAngle);
                var cmds = new List<OfficePathCommand> { OfficePathCommand.MoveTo(os.x, os.y) };
                ArcBeziers(cmds, cx, cy, outerR, startAngle * Math.PI / 180, endAngle * Math.PI / 180);
                cmds.Add(OfficePathCommand.LineTo(ie.x, ie.y));
                ArcBeziers(cmds, cx, cy, innerR, endAngle * Math.PI / 180, startAngle * Math.PI / 180);
                cmds.Add(OfficePathCommand.Close());
                var slice = OfficeShape.Path(ChartViewW, ChartViewH, cmds);
                slice.FillColor = OC(e.colour); slice.StrokeColor = OC(ReportColours.White); slice.StrokeWidth = 1;
                dw.AddShape(slice, ox, oy);
                preceding += e.value;
            }
            // Total in the middle, with an optional caption under it (client centreLabel).
            var centred = string.IsNullOrEmpty(centreLabel);
            AddT(dw, FmtNum(total), ox + ChartViewW / 2 - 40, oy + cy - (centred ? 8 : 13), 80, 16, 14, ReportColours.Ink, OfficeTextAlignment.Center);
            if (!centred)
                AddT(dw, San(centreLabel!), ox + ChartViewW / 2 - 40, oy + cy + 8, 80, 10, 7, ReportColours.Muted, OfficeTextAlignment.Center);
            DrawLegend(ctx, dw, visible, ox, oy, 172);
        }

        private static void DrawLegend(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, double baseY)
        {
            var n = entries.Count;
            var perRow = n <= 3 ? n : (int)Math.Ceiling(n / 2.0);
            var colW = (ChartViewW - 40) / Math.Max(perRow, 1);
            for (var i = 0; i < n; i++)
            {
                var e = entries[i];
                var row = i / perRow; var col = i % perRow;
                var x = 20 + col * colW; var rowY = baseY + row * 14;
                var sw = OfficeShape.Rectangle(8, 8); sw.FillColor = OC(e.colour); dw.AddShape(sw, ox + x, oy + rowY - 6);
                AddT(dw, San($"{e.label} ({FmtNum(e.value)})"), ox + x + 12, oy + rowY - 6, colW - 12, 10, ChartLabelSize, ctx.Theme.Palette["body"], OfficeTextAlignment.Left);
            }
        }

        private static void DrawTrend(ReportContext ctx, OfficeDrawing dw,
            List<(string label, double value, string colour)> entries, double ox, double oy, double? max)
        {
            const double plotLeft = 40, plotTop = 20, plotWidth = 320, plotHeight = 140;
            const double plotBottom = plotTop + plotHeight;
            var colour = ctx.Theme.Primary;
            var dataMax = Math.Max(entries.Max(e => e.value), 0);
            var scaleMax = max is > 0 ? max!.Value : dataMax > 0 ? dataMax : 1;
            var spacing = plotWidth / Math.Max(entries.Count - 1, 1);
            var pts = entries.Select((e, i) => (
                x: plotLeft + i * spacing,
                y: plotBottom - Math.Min(e.value / scaleMax, 1) * plotHeight)).ToList();

            var rect = OfficeShape.Rectangle(plotWidth, plotHeight);
            rect.FillColor = OC(ReportColours.Panel); rect.StrokeColor = OC(ReportColours.Line); rect.StrokeWidth = 1;
            dw.AddShape(rect, ox + plotLeft, oy + plotTop);
            for (var g = 0; g <= 4; g++)
            {
                var gy = plotTop + g * (plotHeight / 4);
                var gl = OfficeShape.Line(0, 0, plotWidth, 0);
                gl.StrokeColor = OC(ReportColours.Line); gl.StrokeWidth = 0.5; dw.AddShape(gl, ox + plotLeft, oy + gy);
            }
            if (pts.Count > 1)
            {
                // Local coords in a 400x200 box placed at the chart offset (see donut note).
                var area = new List<OfficePathCommand> { OfficePathCommand.MoveTo(pts[0].x, pts[0].y) };
                for (var i = 1; i < pts.Count; i++) area.Add(OfficePathCommand.LineTo(pts[i].x, pts[i].y));
                area.Add(OfficePathCommand.LineTo(pts[^1].x, plotBottom));
                area.Add(OfficePathCommand.LineTo(pts[0].x, plotBottom));
                area.Add(OfficePathCommand.Close());
                var areaShape = OfficeShape.Path(ChartViewW, ChartViewH, area); areaShape.FillColor = OC(colour); areaShape.FillOpacity = 0.3; dw.AddShape(areaShape, ox, oy);

                var line = new List<OfficePathCommand> { OfficePathCommand.MoveTo(pts[0].x, pts[0].y) };
                for (var i = 1; i < pts.Count; i++) line.Add(OfficePathCommand.LineTo(pts[i].x, pts[i].y));
                var lineShape = OfficeShape.Path(ChartViewW, ChartViewH, line); lineShape.StrokeColor = OC(colour); lineShape.StrokeWidth = 2; dw.AddShape(lineShape, ox, oy);
            }
            foreach (var p in pts)
            {
                var dot = OfficeShape.Ellipse(6, 6); dot.FillColor = OC(colour); dw.AddShape(dot, ox + p.x - 3, oy + p.y - 3);
            }
            var stride = (int)Math.Ceiling(entries.Count / 7.0);
            for (var i = 0; i < entries.Count; i++)
                if (i % stride == 0)
                    AddT(dw, San(entries[i].label), ox + pts[i].x - 20, oy + plotBottom + 8, 40, 9, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Center);
            foreach (var frac in new[] { 0, 0.25, 0.5, 0.75, 1.0 })
                AddT(dw, FmtNum(Math.Round(scaleMax * frac)), ox, oy + plotBottom - frac * plotHeight - 4, plotLeft - 5, 9, ChartLabelSize, ReportColours.Muted, OfficeTextAlignment.Right);
        }

        private static string RunsToPlain(IReadOnlyList<TextRun> runs)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var r in runs) sb.Append(r.Text);
            return sb.ToString();
        }

        // -- dispatch --
        /// <summary>Render a list of component/primitive nodes into the current item flow. An optional text
        /// style flows into paragraph nodes so a callout renders its body at the callout size, not body copy.</summary>
        public static void RenderNodes(ReportContext ctx, PdfItemCompose item, IEnumerable<ReportNode> nodes, TextStyle? textStyle = null)
        {
            foreach (var node in nodes) RenderNode(ctx, item, node, textStyle);
        }

        private static void RenderNode(ReportContext ctx, PdfItemCompose item, ReportNode node, TextStyle? textStyle = null)
        {
            switch (node.Type)
            {
                case "heading":
                    Heading(ctx, item, (int)(node.Num("level") ?? 2), node.Get<List<TextRun>>("runs") ?? new List<TextRun>());
                    break;
                case "paragraph":
                    Paragraph(ctx, item, node.Get<List<TextRun>>("runs") ?? new List<TextRun>(), textStyle);
                    break;
                case "bullets":
                    // Inside a callout (textStyle set) OfficeIMO panels ignore a per-call list style, so
                    // the list is drawn as one styled paragraph with a marker per line - matching the
                    // client, which renders callout bullets as a single text block. Elsewhere the real
                    // list renderer is used.
                    if (textStyle is { } bts) BulletLines(ctx, item, StringItems(node), bts, _ => "•  ");
                    else Bullets(ctx, item, StringItems(node));
                    break;
                case "numbered":
                    if (textStyle is { } nts)
                    {
                        var start = (int)(node.Num("start") ?? 1);
                        BulletLines(ctx, item, StringItems(node), nts, i => $"{start + i}.  ");
                    }
                    else Numbered(ctx, item, StringItems(node), (int)(node.Num("start") ?? 1));
                    break;
                case "table":
                    RenderTableNode(ctx, item, node);
                    break;
                case "code":
                    Code(ctx, item, node.Str("text") ?? string.Empty);
                    break;
                case "hr":
                    Hr(ctx, item);
                    break;
                default:
                    // Unknown primitive: fall back to its text content as a paragraph.
                    var text = node.Str("content") ?? node.Str("text");
                    if (!string.IsNullOrEmpty(text)) Paragraph(ctx, item, ReportMarkdown.MarkdownRuns(text));
                    break;
            }
        }

        private static void RenderTableNode(ReportContext ctx, PdfItemCompose item, ReportNode node)
        {
            var rows = node.Get<List<string[]>>("rows");
            if (rows is { Count: > 0 }) item.Table(UpperHeader(rows), PdfAlign.Left, BrandedTableStyle(ctx));
        }

        private static List<string> StringItems(ReportNode node)
        {
            var result = new List<string>();
            if (node.Get<List<string>>("items") is { } typed) return typed;
            if (node.ListOf("items") is { } raw) foreach (var o in raw) result.Add(o?.ToString() ?? string.Empty);
            return result;
        }

        /// <summary>
        /// Block -> component adapter for the Report Builder. Each top-level block renders its title as a
        /// section heading, then its body composed from the component kit. Hero/pagebreak are handled by
        /// the document scaffold, not here.
        /// </summary>
        public static void RenderBlock(ReportContext ctx, PdfItemCompose item, ReportNode block, bool firstOnPage = false)
        {
            var content = block.Str("content") ?? string.Empty;

            // Callouts carry their own title inside the box, so they are handled before the generic
            // section-title emit below - the title must not also appear as a heading above the panel.
            switch (block.Type)
            {
                case "infobox":
                    InfoBox(ctx, item, block.Str("title"), block.Str("tone"), block.Str("colour"), block.Bool("tintTitle"), content, block.Bool("lines"));
                    return;
                case "infoboxcolumns":
                    InfoBoxColumns(ctx, item, block.ListOf("items") ?? new List<object?>(), (int)(block.Num("columns") ?? 2));
                    return;
                case "alertbox":
                    AlertBox(ctx, item, block.Str("title"), block.Str("colour"), content, block.Bool("lines"));
                    return;
                case "clearbox":
                    ClearBox(ctx, item, block.Str("title"), content, block.Bool("lines"));
                    return;
                case "paragraphindent":
                    IndentedParagraph(ctx, item, content);
                    return;
                case "note":
                    Note(ctx, item, content);
                    return;
                case "chart":
                    Chart(ctx, item, block.Str("chartKind"), block.ListOf("chartData") ?? new List<object?>(),
                        block.Str("title"), block.Str("caption"), block.Num("max"), block.Str("centreLabel"));
                    return;
            }

            // A titled block opens a new section (client <Section>). Every section but the first on a page
            // carries the client's section marginBottom 12 above its heading, on top of the previous
            // block's own trailing space - so sections sit apart the way they do in the react-pdf reports.
            var title = block.Str("title");
            if (!string.IsNullOrEmpty(title))
            {
                if (!firstOnPage) item.Spacer(SectionGap);
                SectionTitle(ctx, item, title);
            }

            // Test-block status line (Passed/Failed/Investigate/Skipped).
            if (block.Type == "test" && !string.IsNullOrEmpty(block.Str("status")))
                Note(ctx, item, "Status: " + block.Str("status"));

            switch (block.Type)
            {
                case "scorecard":
                    StatRow(ctx, item, block.ListOf("stats") ?? new List<object?>());
                    break;
                case "richtable":
                    RichTable(ctx, item, block.ListOf("columns") ?? new List<object?>(), block.ListOf("rows") ?? new List<object?>(), (int)(block.Num("limit") ?? 0));
                    break;
                case "richbullets":
                    RichBullets(ctx, item, block.ListOf("items") ?? new List<object?>());
                    break;
                case "progress":
                    Progress(ctx, item, block.ListOf("items") ?? new List<object?>());
                    break;
                case "database":
                    var format = block.Str("format");
                    if (!string.IsNullOrEmpty(format) && format != "text") Code(ctx, item, content);
                    else RenderNodes(ctx, item, ReportMarkdown.MarkdownToNodes(content));
                    break;
                case "blank":
                    RenderNodes(ctx, item, ReportMarkdown.HtmlToNodes(content));
                    break;
                case "test":
                    RenderNodes(ctx, item, block.Bool("static")
                        ? ReportMarkdown.HtmlToNodes(content)
                        : ReportMarkdown.MarkdownToNodes(content));
                    break;
                default:
                    // A raw primitive node passed straight through (e.g. from a fixed report composing the kit).
                    RenderNode(ctx, item, block);
                    break;
            }
        }
    }
}
