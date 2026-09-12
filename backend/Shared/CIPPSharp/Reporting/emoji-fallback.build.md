# Emoji rendering: colour Twemoji images + a monochrome fallback font

Emoji render in two tiers. Both are **committed assets, not build outputs** — the Dockerfile ships
them via `COPY backend/Shared` and never rebuilds them.

1. **Colour (primary): the Twemoji PNG set in `bin/twemoji/`** (~4,000 individual 72x72 PNGs, ~4 MB,
   named by lowercase-hex code point, e.g. `26a0.png`, `1f1fa-1f1f8.png`). [`TwemojiAssets`](TwemojiAssets.cs)
   resolves an emoji grapheme cluster (incl. ZWJ sequences, flags, skin tones) to its PNG, and the
   component kit places it as an inline colour image (`PdfParagraphBuilder.InlineImage` in flow text,
   `PdfTextRun.Inline` in table cells). A render only reads the handful of files it embeds; OfficeIMO
   dedupes so each distinct emoji embeds once (~1-1.5 KB in the PDF). This is how the old react-pdf
   reports rendered emoji (Twemoji via `Font.registerEmojiSource`). Attribution: `bin/twemoji/ATTRIBUTION.txt`
   (CC-BY 4.0). Refresh from https://github.com/jdecked/twemoji `assets/72x72/`.

   **Vector-drawing contexts render emoji monochrome, not colour**: the cover, hero and chart
   title/labels are `OfficeDrawing`s (text drawn via a font, not inline images), and the running
   footer's builder has no image API - so emoji there fall back to the font below. Colour in a drawing
   would need manual per-glyph image layout (text measurement + positioning). Emoji are uncommon in
   those branded/chrome contexts, so they are left monochrome.

2. **Monochrome fallback: `bin/emoji-fallback.ttf`** (internal family **CippReportEmoji**, ~800 KB).
   Used for any emoji the Twemoji set lacks, and in the drawing/footer contexts above. The standard PDF
   fonts have no emoji glyphs, so [`ReportMarkdown.Sanitize`](ReportMarkdown.cs) keeps any emoji this
   font can draw and OfficeIMO routes each such code point through it per character, while the
   surrounding text stays in the standard font. The three report emoji (⚠ ✅ ℹ) are tinted to their
   brand colour on this path; everything else renders in the surrounding text colour. Regenerate it only
   to widen coverage or refresh the upstreams (below).

## What it is

A subset+merge of two redistributable upstreams (see `bin/emoji-fallback.LICENSE.txt`):

| Glyphs | Source | Licence |
| --- | --- | --- |
| Latin-1 (`U+0020-00FF`) + CP1252 specials | DejaVu Sans | Bitstream Vera / Arev |
| Symbols & emoji, BMP + astral | Noto Emoji (monochrome) | SIL OFL 1.1 |

The Latin-1 glyphs are there only so OfficeIMO's greedy "neighbour of an emoji" fallback never
lands on an uncovered character; ordinary text never routes to this font because those code points
are excluded from the declared fallback ranges (below).

## Recipe (fonttools + Python)

```bash
# Sources
#   DejaVu Sans:  https://dejavu-fonts.github.io/  (DejaVuSans.ttf, 2048 upem)
#   Noto Emoji:   https://github.com/google/fonts/raw/main/ofl/notoemoji/NotoEmoji%5Bwght%5D.ttf

# 1. Instance the Noto Emoji variable font to a static regular weight (also 2048 upem)
python -c "from fontTools.ttLib import TTFont; from fontTools.varLib.instancer import instantiateVariableFont; \
  f=TTFont('NotoEmoji[wght].ttf'); instantiateVariableFont(f,{'wght':400},inplace=True); f.save('NotoEmoji-Static.ttf')"

# 2. Subset each. DejaVu = Latin-1 + CP1252 specials; Noto = symbol/emoji ranges, EXCLUDING U+2122 (TM,
#    which DejaVu supplies) so the two cmaps do not collide on merge.
python -m fontTools.subset DejaVuSans.ttf --output-file=dejavu-latin.ttf --no-hinting --desubroutinize \
  --unicodes="0020-00FF,20AC,201A,0192,201E,2026,2020,2021,02C6,2030,0160,2039,0152,017D,2018,2019,201C,201D,2022,2013,2014,02DC,2122,0161,203A,0153,017E,0178"
python -m fontTools.subset NotoEmoji-Static.ttf --output-file=noto-sub.ttf --no-hinting --desubroutinize \
  --unicodes="2100-2121,2123-27BF,2B00-2BFF,1F004,1F0CF,1F170-1F251,1F300-1F6FF,1F7E0-1F7EB,1F900-1F9FF,1FA70-1FAFF"

# 3. Strip tables fontTools.merge cannot combine (Noto ships a MATH table), keeping only the essentials.
python -c "from fontTools.ttLib import TTFont; keep={'glyf','loca','cmap','head','hhea','hmtx','maxp','name','OS/2','post','gasp'}; \
  [ ( (lambda f:[ [f.__delitem__(t) for t in list(f.keys()) if t not in keep], f.save(fn)])(TTFont(fn)) ) for fn in ('dejavu-latin.ttf','noto-sub.ttf') ]"

# 4. Merge and rename the family so no upstream reserved font name survives.
python -c "from fontTools import merge; f=merge.Merger().merge(['dejavu-latin.ttf','noto-sub.ttf']); \
  n=f['name']; [n.setName('CippReportEmoji',i,3,1,0x409) for i in (1,16)]; [n.setName('CippReportEmoji-Regular',i,3,1,0x409) for i in (4,6)]; \
  f.save('emoji-fallback.ttf')"
```

Both upstreams must share `unitsPerEm` (2048) or the merged glyphs mis-scale. Verify the result has a
Windows BMP `cmap` (platform 3, encoding 1, format 4) **and** a full `cmap` (3/10, format 12 — this is
what carries the astral emoji).

## How the code stays in sync with the font

Nothing hard-codes the code points. At render time [`FontCmap`](FontCmap.cs) reads this font's own
`cmap`; `ReportPdf` keeps the code points above `U+00FF` (minus the CP1252 specials) as both the
`Sanitize` keep-set and the OfficeIMO fallback ranges (coalesced to OfficeIMO's 128-range limit). So
widening coverage is just a re-subset here — no C# change. If you drop this file, emoji degrade to
ASCII tokens rather than throwing.
