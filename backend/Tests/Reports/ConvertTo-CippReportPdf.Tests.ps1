# Pester tests for ConvertTo-CippReportPdf and the CIPPSharp component kit it wraps.
# Verifies every block type renders to a valid PDF, empty input still produces a page, branding is
# applied without throwing, and the image-fit invariant (OfficeIMO throws on over-tall images) holds.

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

    Context 'Image fit invariant' {
        It 'scales an over-tall image into the max box (height never exceeds the cap)' {
            $fit = [CIPP.Reporting.ReportComponents]::FitImage($script:TinyPng, 100, 5000, 180.0, 90.0)
            $fit | Should -Not -BeNullOrEmpty
            $fit.Item3 | Should -BeLessOrEqual 90
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
