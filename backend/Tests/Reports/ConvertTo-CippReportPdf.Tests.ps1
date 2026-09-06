# Pester tests for ConvertTo-CippReportPdf and the CIPPSharp component kit it wraps.
# Verifies every block type renders to a valid PDF, empty input still produces a page, branding is
# applied without throwing, and every image format the engine accepts decodes and renders.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    $HelperPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CippReportPdf.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $HelperPath) { throw 'Could not locate ConvertTo-CippReportPdf.ps1 under Modules/' }
    . $HelperPath
    # The wrapper resolves branding itself when none is passed; keep that offline.
    function Get-CIPPBrandingSettings { @{} }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) @() }

    function Test-IsPdf {
        param($Bytes)
        if ($Bytes -isnot [byte[]] -or $Bytes.Length -lt 100) { return $false }
        return ([System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) -eq '%PDF-')
    }

    # 1x1 transparent PNG.
    $script:TinyPng = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
}

Describe 'ConvertTo-CippReportPdf' {
    Context 'Block types render to a valid PDF' {
        It 'renders a blank (HTML) block with marks and a list' {
            $b = @(@{ type = 'blank'; title = 'Summary'; content = '<p>Hello <strong>world</strong> and <em>more</em></p><ul><li>one</li><li>two</li></ul>' })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b -TenantName 'Contoso' -ReportName 'T') | Should -BeTrue
        }
        It 'renders a markdown test block with a status and a table' {
            $md = "## Details`n`nUsers without **MFA** are exposed. SKU ``SPE_E5`` stays literal.`n`n| Setting | State |`n|---|---|`n| MFA | Off |"
            $b = @(@{ type = 'test'; title = 'MFA'; status = 'Failed'; static = $false; content = $md })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a database markdown table block' {
            $b = @(@{ type = 'database'; title = 'Users'; format = 'text'; content = "| Name | UPN |`n|---|---|`n| Bob | bob@x.com |" })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a database csv/json block as a code block' {
            $b = @(@{ type = 'database'; title = 'Raw'; format = 'json'; content = '[{"a":1}]' })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a scorecard block' {
            $b = @(@{ type = 'scorecard'; title = 'At a glance'; stats = @(@{ value = '3'; label = 'Anon' }, @{ value = '7'; label = 'No expiry' }) })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a chart block' {
            $b = @(@{ type = 'chart'; title = 'By risk'; chartData = @(@{ label = 'High'; value = 5 }, @{ label = 'Low'; value = 9 }) })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders a hero and a page break without throwing' {
            $b = @(@{ type = 'hero'; title = 'Chapter'; heroHighlight = '39' }, @{ type = 'pagebreak' }, @{ type = 'blank'; content = '<p>after</p>' })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
    }

    Context 'Edge cases' {
        It 'renders an empty component tree as a valid one-page PDF' {
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks @()) | Should -BeTrue
        }
        It 'applies a branding colour without throwing' {
            $b = @(@{ type = 'blank'; content = '<p>x</p>' })
            $branding = @{ colour = '#0E4C92'; secondaryColour = '#F77F00'; watermarkText = 'DRAFT'; watermarkEnabled = $true; footerText = '%tenantname% report' }
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b -Branding $branding -TenantName 'Contoso') | Should -BeTrue
        }
        It 'still renders when the branding logo cannot be embedded (skips it gracefully)' {
            $b = @(@{ type = 'blank'; content = '<p>x</p>' })
            # An unusable logo (here a PNG OfficeIMO rejects) must not sink the whole report.
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b -Branding @{ logo = $script:TinyPng }) | Should -BeTrue
        }
        It 'accepts a pre-serialised JSON block string' {
            $json = ConvertTo-Json -InputObject @(@{ type = 'blank'; content = '<p>json</p>' }) -Depth 10
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $json) | Should -BeTrue
        }
    }

    Context 'Image formats' {
        BeforeAll {
            # 1x1 fixtures: the smallest valid GIF and WebP, a two-colour SVG, and a corrupt PNG.
            $script:Gif = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'
            $script:Webp = 'data:image/webp;base64,UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA'
            $script:Svg = 'data:image/svg+xml;base64,' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#F77F00"/></svg>'))
            $script:Block = @(@{ type = 'blank'; title = 'Formats'; content = '<p>x</p>' })
        }
        It 'identifies every raster OfficeIMO decodes, not just PNG and JPEG' {
            [CIPP.Reporting.ReportComponents]::ImageContentType([CIPP.Reporting.ReportComponents]::DecodeImage($script:Gif)) | Should -Be 'image/gif'
            [CIPP.Reporting.ReportComponents]::ImageContentType([CIPP.Reporting.ReportComponents]::DecodeImage($script:Webp)) | Should -Be 'image/webp'
        }
        It 'rasterises an SVG once at decode time so every placement sees a PNG' {
            $bytes = [CIPP.Reporting.ReportComponents]::DecodeImage($script:Svg)
            [CIPP.Reporting.ReportComponents]::ImageContentType($bytes) | Should -Be 'image/png'
            # 40x20 source scaled to 1200px on the long side, aspect kept.
            $size = [CIPP.Reporting.ReportComponents]::ImageSize($bytes)
            $size.Item1 | Should -Be 1200
            $size.Item2 | Should -Be 600
        }
        It 'drops what OfficeIMO cannot identify rather than failing the render' {
            [CIPP.Reporting.ReportComponents]::DecodeImage($script:TinyPng) | Should -BeNullOrEmpty
            [CIPP.Reporting.ReportComponents]::DecodeImage('data:image/png;base64,' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('not an image'))) | Should -BeNullOrEmpty
        }
        It 'renders a GIF logo, an SVG logo and a WebP cover' {
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $script:Block -Branding @{ logo = $script:Gif }) | Should -BeTrue
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $script:Block -Branding @{ logo = $script:Svg }) | Should -BeTrue
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $script:Block -Branding @{ coverImage = $script:Webp; logo = $script:Webp }) | Should -BeTrue
        }
    }

    Context 'Emoji rendering' {
        BeforeAll {
            # A render populates the emoji flags (font coverage from the cmap; Twemoji image assets present).
            $null = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; content = '<p>x</p>' })
        }
        It 'renders arbitrary BMP and astral emoji (incl. a ZWJ sequence) alongside text without throwing' {
            $party = [char]::ConvertFromUtf32(0x1F389)   # astral (surrogate pair)
            $rocket = [char]::ConvertFromUtf32(0x1F680)  # astral
            $star = [char]0x2B50                         # BMP symbol
            $dev = [char]::ConvertFromUtf32(0x1F469) + [char]0x200D + [char]::ConvertFromUtf32(0x1F4BB) # woman technologist (ZWJ)
            $b = @(@{ type = 'blank'; content = "<p>Great work $party a rocket $rocket a star $star a dev $dev and warning [!]</p>" })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'renders emoji inside a callout (table cell) without throwing' {
            $party = [char]::ConvertFromUtf32(0x1F389)
            $b = @(@{ type = 'infobox'; title = "Alert $party"; tone = 'warn'; content = "Body [!] with a rocket $([char]::ConvertFromUtf32(0x1F680))." })
            Test-IsPdf (ConvertTo-CippReportPdf -Blocks $b) | Should -BeTrue
        }
        It 'loads the bundled monochrome font coverage and the Twemoji image assets' {
            [CIPP.Reporting.ReportMarkdown]::RenderEmojiGlyphs | Should -BeTrue
            [CIPP.Reporting.ReportMarkdown]::EmojiCoverage.Count | Should -BeGreaterThan 100
            [CIPP.Reporting.ReportMarkdown]::RenderEmojiImages | Should -BeTrue
        }
        It 'keeps a colour emoji (which the renderer draws as an image) rather than stripping it' {
            # A red circle has a Twemoji asset, so Sanitize keeps it verbatim for the image renderer.
            [CIPP.Reporting.ReportMarkdown]::Sanitize([char]::ConvertFromUtf32(0x1F534)) | Should -Be ([char]::ConvertFromUtf32(0x1F534))
        }
        It 'promotes the status tokens to their colour glyphs' {
            [CIPP.Reporting.ReportMarkdown]::Sanitize('[Pass]') | Should -Be '✅'
            [CIPP.Reporting.ReportMarkdown]::Sanitize('[Fail]') | Should -Be '❌'
        }
    }
}

Describe 'Watermark layering' {
    # OfficeIMO paints the watermark first; the engine moves its operator block to the end of each page's
    # content stream so it sits over the content, on content pages and dark divider pages alike.
    It 'draws the watermark after everything else on every page that carries one' {
        $Blocks = @(
            @{ type = 'scorecard'; title = 'Figures'; stats = @(@{ value = '1'; label = 'One' }, @{ value = '2'; label = 'Two' }) }
            @{ type = 'hero'; title = 'Divider'; heroHighlight = '83%'; heroSubText = 'of controls in place' }
            @{ type = 'blank'; title = 'After the divider'; content = '<p>Body text under the mark.</p>' }
        )
        $Bytes = ConvertTo-CippReportPdf -Blocks $Blocks -Variables @{} -Branding @{ colour = '#0E4C92'; watermarkText = 'Preview'; watermarkEnabled = $true } -TenantName 'Contoso' -ReportName 'T'
        $Pdf = [System.Text.Encoding]::Latin1.GetString($Bytes)
        $Marker = '<50524556494557> Tj'
        $Streams = [regex]::Matches($Pdf, '(?s)<< /Length (\d+) >>\s*stream\n(.*?)\nendstream') | ForEach-Object { $_.Groups[2].Value }
        $Marked = @($Streams | Where-Object { $_.Contains($Marker) })
        # a content page and the divider at least; the cover never carries one
        $Marked.Count | Should -BeGreaterOrEqual 2
        $Streams[0] | Should -Not -Match 'Tj\s*ET\s*Q\s*$'
        foreach ($Data in $Marked) {
            $Data.TrimEnd() | Should -Match "$([regex]::Escape($Marker))\s*ET\s*Q$"
            ([regex]::Matches($Data, '> Tj|\) Tj') | Select-Object -Last 1).Value | Should -Be '> Tj'
            $Data.LastIndexOf(' re') | Should -BeLessThan $Data.IndexOf($Marker)
        }
    }

    It 'leaves a document without a watermark untouched' {
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92' } -TenantName 'Contoso' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
        [System.Text.Encoding]::Latin1.GetString($Bytes) | Should -Not -Match '0\.707 -0\.707 0\.707 0\.707'
    }
}

Describe 'Tenant name in the branding text' {
    It 'substitutes %tenantname% with the name the report was given, before the cache-based replacement runs' {
        $script:Seen = @()
        function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $script:Seen += $Text; $Text -replace '%tenantname%', 'CacheName' }
        $Bytes = ConvertTo-CippReportPdf -Blocks @(@{ type = 'blank'; title = 'T'; content = '<p>x</p>' }) -Variables @{} -Branding @{ colour = '#0E4C92'; footerText = 'Prepared for %TenantName%'; watermarkText = '%tenantname%' } -TenantName 'contoso.onmicrosoft.com' -TenantFilter 'contoso.onmicrosoft.com' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
        $Branding = $script:Seen | Where-Object { $_ -like '*footerText*' } | Select-Object -First 1
        $Branding | Should -Match 'Prepared for contoso\.onmicrosoft\.com'
        $Branding | Should -Match '"watermarkText":"contoso\.onmicrosoft\.com"'
        $Branding | Should -Not -Match '(?i)%tenantname%'
    }
}
