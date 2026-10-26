# Builds the PDF benchmark corpus: fixtures/<name>.json = { blocks, variables, branding, tenant, reportName, landscape },
# the exact inputs [CIPP.Reporting.ReportPdf]::Render takes. The corpus is every CIPP report (the branding-preview
# samples from backend/Config/ReportSamples, rendered through their real tree builders), the Pester report trees,
# a showcase of every block type the kit renders (portrait and landscape), and stress cases (long tables, a BEC
# report with every list x40). No DLL is needed here - only the PS tree builders. Windows only (System.Drawing
# draws the sample logo). Re-run after a builder change and commit the regenerated fixtures with it:
#   pwsh ./build/tools/pdf-bench/Export-PdfBenchFixtures.ps1
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '../../../backend')).Path
$Out = Join-Path $PSScriptRoot 'fixtures'
$null = New-Item -ItemType Directory -Force $Out
Get-ChildItem "$Root/Modules/CIPPCore/Public/Tools/Reporting" -Filter *.ps1 | ForEach-Object { . $_.FullName }
function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

# -- brandings --
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new(240, 80)
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse([System.Drawing.Brushes]::DarkCyan, 4, 4, 72, 72)
$g.DrawString('Contoso', [System.Drawing.Font]::new('Arial', 26, [System.Drawing.FontStyle]::Bold), [System.Drawing.Brushes]::DarkSlateGray, 84, 18)
$ms = [System.IO.MemoryStream]::new(); $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$PngLogo = 'data:image/png;base64,' + [Convert]::ToBase64String($ms.ToArray())
$Svg = '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="80" viewBox="0 0 240 80"><circle cx="40" cy="40" r="36" fill="#0f766e"/><rect x="84" y="22" width="140" height="14" rx="7" fill="#334155"/><rect x="84" y="44" width="100" height="10" rx="5" fill="#94a3b8"/><path d="M22 40 L36 54 L60 26" stroke="#fff" stroke-width="7" fill="none" stroke-linecap="round"/></svg>'
$SvgLogo = 'data:image/svg+xml;base64,' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Svg))
$BrandFull = @{ colour = '#1F6FEB'; secondaryColour = '#F77F00'; logo = $PngLogo; coverStock = '/reportImages/city.jpg'; footerText = '%tenantname% - Confidential - %reportdate%'; showFooter = $true; showPageNumbers = $true; watermarkText = 'Draft %tenantname%'; watermarkEnabled = $true }
$BrandSvg = @{ colour = '#0F766E'; logo = $SvgLogo; coverStock = '/reportImages/board.jpg'; footerText = 'Prepared for %tenantname%'; showFooter = $true; showPageNumbers = $true; watermarkEnabled = $false }
$BrandMin = @{ colour = '#F77F00' }

function Save($Name, $Blocks, $Variables, $Branding, [string]$Tenant = 'Contoso', [string]$ReportName = 'Report', [switch]$Landscape) {
    $obj = [ordered]@{
        blocks     = (ConvertTo-Json -InputObject @($Blocks) -Depth 30 -Compress)
        variables  = (ConvertTo-Json -InputObject ($(if ($Variables) { $Variables } else { @{} })) -Depth 6 -Compress)
        branding   = (ConvertTo-Json -InputObject $Branding -Depth 6 -Compress)
        tenant     = $Tenant; reportName = $ReportName; landscape = [bool]$Landscape
    }
    ConvertTo-Json -InputObject $obj -Depth 3 | Set-Content -Encoding utf8 (Join-Path $Out "$Name.json")
}

# ================= (a) showcase =================
$Emoji = [string]::Concat([char]::ConvertFromUtf32(0x2705), ' ', [char]::ConvertFromUtf32(0x274C), ' ', [char]::ConvertFromUtf32(0x26A0), [char]0xFE0F, ' ', [char]::ConvertFromUtf32(0x1F512), ' ', [char]::ConvertFromUtf32(0x1F680), ' ', [char]::ConvertFromUtf32(0x1F1E6), [char]::ConvertFromUtf32(0x1F1FA))
$Ok = [char]::ConvertFromUtf32(0x2705); $No = [char]::ConvertFromUtf32(0x274C); $Warn = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
$Lorem = 'Identity is the perimeter: every control in this report starts with who can sign in, from where, and on what device. This paragraph is deliberately long so it wraps over several lines at body size and exercises line breaking, justification-free left alignment, and the paragraph spacing that follows it before the next block begins.'
$Tones = 'pass', 'warn', 'fail', 'muted', ''
$Colours = '#16a34a', '#d97706', '#dc2626', '#2563eb', '#7c3aed'
$LongRows = foreach ($i in 1..320) {
    [ordered]@{ n = "$i"; user = "user$('{0:D3}' -f $i)@contoso.onmicrosoft.com"; dept = @('Finance', 'Engineering', 'Sales and Marketing Operations', 'HR', 'Legal')[$i % 5]
        state = @('Compliant', 'Drift', 'Failed', 'Not evaluated', 'Unknown')[$i % 5]; tone = $Tones[$i % 5]
        risk = @('Low', 'Medium', 'High', 'Critical', 'Info')[$i % 5]; riskColour = $Colours[$i % 5]
        note = $(if ($i % 7 -eq 0) { "A longer free-text note for row $i that wraps inside its cell to make the row taller than its neighbours $Ok" } else { 'n/a' }) }
}
$LongCols = @(
    @{ header = '#'; key = 'n'; width = 0.4; align = 'right' }
    @{ header = 'User'; key = 'user'; width = 2.4; bold = $true }
    @{ header = 'Department'; key = 'dept'; width = 1.4 }
    @{ header = "State $Ok"; key = 'state'; width = 1.1; toneField = 'tone'; align = 'center' }
    @{ header = 'Risk'; key = 'risk'; width = 0.8; colourField = 'riskColour' }
    @{ header = 'Note'; key = 'note'; width = 2.2 }
)
$Html = @"
<h1>Heading one</h1><h2>Heading two</h2><h3>Heading three</h3>
<p>Body with <strong>bold</strong>, <em>italic</em>, <code>inline code</code>, <s>strike</s>, <u>underline</u> and a <a href="https://example.com">link</a>. Emoji: $Emoji</p>
<ul><li>First bullet</li><li>Second bullet with <strong>bold</strong></li><li>$Ok Passed item</li></ul>
<ol><li>Step one</li><li>Step two</li><li>Step three</li></ol>
<pre><code>Get-Mailbox -ResultSize Unlimited | Select DisplayName
  | Where-Object { `$_.RecipientTypeDetails -eq 'SharedMailbox' }</code></pre>
<blockquote>A quoted remark from the customer.</blockquote>
<table><thead><tr><th>Control</th><th>Status</th><th>Owner</th></tr></thead><tbody><tr><td>MFA</td><td>$Ok Enabled</td><td>IT</td></tr><tr><td>Legacy auth</td><td>$No Allowed</td><td>Security</td></tr><tr><td>Guests</td><td>$Warn Review</td><td>HR</td></tr></tbody></table>
<p>$Lorem</p>
"@
$Markdown = @"
14 of 128 accounts can still sign in **without** a second factor. *Italic*, ``code``, ~~strike~~.

# Markdown H1
## Results
### Detail $Warn

- bullet one
- bullet **two**
- bullet three $Ok

3. numbered three
4. numbered four

---

| Account | Method | Last sign-in |
| --- | --- | --- |
| sample.one@example.com | None $No | 2 days ago |
| sample.two@example.com | SMS $Warn | 9 days ago |
| sample.three@example.com | Authenticator $Ok | today |

``````
{ "policies": 191, "enabled": 5 }
``````

$Lorem
"@
$Showcase = @(
    @{ type = 'cover'; title = 'Component'; coverAccent = 'Showcase'; subtitle = 'Every block type the kit renders, for the OfficeIMO upgrade A/B.'; coverLabel = 'Regression Fixture' }
    @{ type = 'blank'; title = 'HTML content'; content = $Html }
    (New-CippReportHeading -Title 'A heading on its own')
    (New-CippReportParagraph -Text $Lorem -Title 'Plain paragraph')
    (New-CippReportParagraph -Text 'Indented under the heading, a detail line that steps in.' -Indent -Title 'Indented paragraph')
    (New-CippReportNote -Text "A small italic aside note. $Emoji")
    (New-CippReportInfoBox -Title 'Info box default' -Content "Identity is the perimeter: **every** control starts with who can sign in.`n`n- a bullet inside`n- another $Ok")
    (New-CippReportInfoBox -Title 'Info box ok tone' -Content 'Everything checked out.' -Tone ok)
    (New-CippReportInfoBox -Title 'Info box warn tone' -Content 'Something needs attention.' -Tone warn -TintTitle)
    (New-CippReportInfoBox -Title 'Info box custom colour, lines' -Content "User: alice@contoso.com`nIP: 203.0.113.9`nCountry: AU $Emoji" -Colour '#7c3aed' -Lines)
    (New-CippReportAlertBox -Title 'Alert box' -Content "A **warning** callout with markdown.`n`n1. first`n2. second")
    (New-CippReportAlertBox -Title 'Alert box lines' -Content "Line one`nLine two`nLine three" -Colour '#dc2626' -Lines)
    (New-CippReportClearBox -Title 'Clear box' -Content ('Neutral callout body text that wraps. ' * 4))
    (New-CippReportClearBox -Title 'Clear box lines' -Content "a: 1`nb: 2" -Lines)
    (New-CippReportInfoBoxColumns -Columns 2 -Items @(@{ title = 'Done'; content = 'Passwordless rolled out to 40% of staff.' }, @{ title = 'Next'; content = 'Extend to remaining sites.'; tone = 'warn' }, @{ title = 'Third'; content = 'Wraps onto a second row.'; colour = '#16a34a'; tintTitle = $true }))
    (New-CippReportInfoBoxColumns -Columns 3 -Items @(@{ title = 'One'; content = 'Short.' }, @{ title = 'Two'; content = 'A longer body that wraps in the narrow column across lines.' }, @{ title = 'Three'; content = 'Ok'; tone = 'ok' }))
    @{ type = 'page'; title = 'Numbers and charts'; subtitle = 'Stat rows, progress, bar/donut/trend, sankey' }
    (New-CippReportStatRow -Title 'Stat row' -Stats @(@{ value = '128'; label = 'Licensed Users' }, @{ value = '96'; label = 'Devices'; caption = '12 non-compliant' }, @{ value = '3'; label = 'Global Admins'; caption = 'Target: 2-4'; colour = '#dc2626' }, @{ value = '9'; label = 'Guests' }))
    (New-CippReportStatRow -Stats @(@{ value = '61%'; label = 'Secure Score' }, @{ value = '0'; label = 'Zero' }, @{ value = '1,234,567'; label = 'Big number that is long'; colour = '#16a34a' }, @{ value = 'N/A'; label = 'Text' }, @{ value = '7'; label = 'Fifth' }, @{ value = '8'; label = 'Sixth' }))
    (New-CippReportProgress -Title 'Progress incl. zero and over-max' -Items @(@{ label = 'MFA enforced'; value = 92; max = 100 }, @{ label = 'Zero value'; value = 0; max = 100 }, @{ label = 'Over max'; value = 130; max = 100 }, @{ label = 'Raw count'; value = 7; max = 20; display = '7 of 20'; colour = '#7c3aed' }, @{ label = 'Full'; value = 100; max = 100 }))
    (New-CippReportChart -Title 'Bar chart' -Kind bar -Data @(@{ label = 'Windows'; value = 62 }, @{ label = 'macOS'; value = 18 }, @{ label = 'iOS'; value = 12 }, @{ label = 'Android'; value = 4 }, @{ label = 'Linux'; value = 1 }))
    (New-CippReportChart -Title 'Donut with centre label' -Kind donut -Data @(@{ label = 'Compliant'; value = 78 }, @{ label = 'Non-compliant'; value = 14; colour = '#dc2626' }, @{ label = 'Not evaluated'; value = 4 }) -CentreLabel 'Devices')
    (New-CippReportChart -Title 'Trend with max + caption' -Kind trend -Max 100 -Caption 'Current: 61 / 100 (61%)' -Data @(1..12 | ForEach-Object { @{ label = "W$_"; value = 40 + [math]::Round(20 * [math]::Sin($_ / 2)) } }))
    (New-CippReportChart -Title 'Empty chart' -Kind bar -Data @())
    @{ type = 'chart'; width = 'half'; title = 'Half bar'; chartKind = 'bar'; chartData = @(@{ label = 'A'; value = 5 }, @{ label = 'B'; value = 9 }, @{ label = 'C'; value = 2 }) }
    @{ type = 'chart'; width = 'half'; title = 'Half donut'; chartKind = 'donut'; chartCentreLabel = 'Total'; chartData = @(@{ label = 'Yes'; value = 30 }, @{ label = 'No'; value = 12 }) }
    @{ type = 'chart'; width = 'half'; title = 'Half trend'; chartKind = 'trend'; chartMax = 50; chartCaption = 'caption'; chartData = @(@{ label = 'Jan'; value = 10 }, @{ label = 'Feb'; value = 30 }, @{ label = 'Mar'; value = 25 }, @{ label = 'Apr'; value = 45 }) }
    @{ type = 'chart'; width = 'half'; title = 'Half donut 2'; chartKind = 'donut'; chartData = @(@{ label = 'Only'; value = 1 }) }
    @{ type = 'chart'; width = 'half'; title = 'Lone half bar'; chartKind = 'bar'; chartData = @(@{ label = 'X'; value = 3 }, @{ label = 'Y'; value = 6 }) }
    (New-CippReportSankey -Title 'Sankey flow' -Caption 'Mail flow by disposition' -Nodes @(
            @{ id = 'in'; label = 'Inbound'; nodeColor = '#2563eb' }, @{ id = 'good'; label = 'Delivered'; nodeColor = 'hsl(140, 60%, 40%)' }, @{ id = 'spam'; label = 'Spam'; nodeColor = '#d97706' }
            @{ id = 'phish'; label = 'Phish'; nodeColor = '#dc2626' }, @{ id = 'inbox'; label = 'Inbox'; nodeColor = '#16a34a' }, @{ id = 'junk'; label = 'Junk'; nodeColor = '#64748b' }
        ) -Links @(@{ source = 'in'; target = 'good'; value = 900 }, @{ source = 'in'; target = 'spam'; value = 80 }, @{ source = 'in'; target = 'phish'; value = 20 }, @{ source = 'good'; target = 'inbox'; value = 850 }, @{ source = 'good'; target = 'junk'; value = 50 }))
    (New-CippReportSankey -Title 'Empty sankey' -Nodes @() -Links @())
    @{ type = 'page'; title = 'Tables and lists' }
    (New-CippReportTable -Title "Rich table with tone/colour/bold/align + emoji header $Ok" -Columns $LongCols -Rows @($LongRows | Select-Object -First 30) -Limit 12)
    (New-CippReportBullets -Title 'Rich bullets' -Items @(@{ label = 'MFA is enforced.'; text = 'All 128 licensed users are covered.' }, @{ text = "No label, just text with emoji $Emoji" }, @{ label = '1.'; text = 'custom marker'; marker = '1.' }, @{ label = 'Long.'; text = $Lorem }))
    @{ type = 'bullets'; items = @('raw bullets primitive', "second $Ok", 'third') }
    @{ type = 'numbered'; start = 5; items = @('raw numbered starts at 5', 'six', 'seven') }
    @{ type = 'code'; text = "raw code primitive`n  indented line`n`tTabbed" }
    @{ type = 'hr' }
    @{ type = 'database'; title = 'Database text'; format = 'text'; content = "| Policy | Identifier | State |`n| --- | --- | --- |`n| Baseline | 8f2a1c4e-6b3d-4f5a-9e7c-1d2b3a4c5e6f | Enabled |`n| Hardened | Microsoft_Defender_for_Business_Servers | Report only |" }
    @{ type = 'database'; title = 'Database json'; format = 'json'; content = "{`n  `"tenant`": `"contoso.com`",`n  `"policies`": 191`n}" }
    @{ type = 'test'; title = 'Test markdown (failed)'; status = 'Failed'; static = $false; content = $Markdown }
    @{ type = 'test'; title = 'Test static HTML'; status = 'Passed'; static = $true; content = '<p>Static <strong>HTML</strong> test body.</p><ul><li>a</li><li>b</li></ul>' }
    @{ type = 'pagebreak' }
    @{ type = 'hero'; title = 'seconds'; heroHighlight = '39'; heroSubText = 'a business falls victim to ransomware'; heroFooterText = 'Proactive defense beats reactive recovery'; heroImage = '/reportImages/working.jpg' }
    (New-CippReportHero -Overtitle 'CHAPTER 2' -Highlight '87%' -Headline 'of breaches start with identity' -SubText 'No photo on this one' -FooterText 'Source: sample')
    @{ type = 'page'; title = 'Long multi-page table'; subtitle = '320 rows, no limit' }
    (New-CippReportTable -Title 'Every user' -Columns $LongCols -Rows @($LongRows) -Limit 0)
    (New-CippReportParagraph -Text 'After the long table.' -Title 'Tail')
)
Save 'showcase' $Showcase @{} $BrandFull -ReportName 'Component Showcase'
Save 'showcase-landscape' $Showcase @{} $BrandFull -ReportName 'Component Showcase' -Landscape
Save 'longtable' @(@{ type = 'page'; title = 'Long table' }, (New-CippReportTable -Title 'Every user' -Columns $LongCols -Rows @($LongRows) -Limit 0)) @{} $BrandMin -ReportName 'Long Table'
# Four times the rows, for how cost scales with page count.
$XlRows = @(foreach ($n in 0..3) { foreach ($Row in $LongRows) { $Copy = [ordered]@{}; foreach ($k in $Row.Keys) { $Copy[$k] = $Row[$k] }; $Copy['n'] = [string]([int]$Row['n'] + 320 * $n); $Copy } })
Save 'longtable-xl' @(@{ type = 'page'; title = 'Long table' }, (New-CippReportTable -Title 'Every user' -Columns $LongCols -Rows $XlRows -Limit 0)) @{} $BrandMin -ReportName 'Long Table'

# ================= (b) fixed reports: Pester fixtures (minimal branding) =================
$r = Build-CippSharingReportTree -Data @{ TenantName = 'Contoso'; summary = @{ totalLinks = 4; itemsShared = 3; externalRecipients = 1; anonymousEditLinks = 1; neverExpiringAnonymous = 1 }; links = @(@{ fileName = 'a.docx'; siteName = 'S'; classification = 'Anonymous'; roles = @('write'); itemType = 'File' }); topRecipients = @(@{ recipient = 'x@example.com'; links = 1 }); topLibraries = @() }
Save 'pester-sharing' $r.Blocks $r.Variables $BrandMin -ReportName 'T'
$r = Build-CippPermissionsReportTree -Data @{ TenantName = 'Contoso'; summary = @{ uniquePermissionLibraries = 1; sitesScanned = 2; librariesScanned = 3; totalAssignments = 5 }; assignments = @(@{ principalId = 'p1'; scope = 'Library'; siteName = 'S'; libraryTitle = 'Docs'; title = 'Bob'; permissionLevel = 'Edit'; principalType = 'User' }) }
Save 'pester-permissions' $r.Blocks $r.Variables $BrandMin -ReportName 'T'
$r = Build-CippMailFlowReportTree -Data @{ TenantName = 'Contoso'; days = 7; totals = @{ GoodMail = 90; EmailPhish = 10 }; daily = @(@{ date = '2026-09-01'; GoodMail = 90; EmailPhish = 10 }); topSenders = @(@{ name = 'a@contoso.com'; count = 5 }) }
Save 'pester-mailflow' $r.Blocks $r.Variables $BrandMin -ReportName 'T'
$r = Build-CippMailFlowReportTree -Data @{ TenantName = 'Contoso' }
Save 'pester-mailflow-empty' $r.Blocks $r.Variables $BrandMin -ReportName 'T'
$r = Build-CippShadowAIReportTree -Data @{ TenantName = 'Contoso'; summary = @{ aiToolsDetected = 2 }; detectedApps = @(@{ aiTool = 'ChatGPT'; vendor = 'OpenAI'; category = 'Chat'; status = 'Sanctioned'; deviceCount = 3; risk = 'High' }); consentedApps = @(@{ aiTool = 'ChatGPT'; vendor = 'OpenAI'; category = 'Chat'; status = 'Sanctioned'; activeUsersLast7Days = 5; risk = 'High' }); topTools = @(); byRisk = @(@{ risk = 'High'; tools = 1 }) }
Save 'pester-shadowai' $r.Blocks $r.Variables $BrandMin -ReportName 'T'
$r = Build-CippExecutiveReportTree -Data @{
    TenantName = 'Contoso'
    UserStats = @{ licensedUsers = 10; unlicensedUsers = 1; guests = 2; globalAdmins = 1; permanentGlobalAdmins = 1; eligibleGlobalAdmins = 0; pimCapable = $true }
    SecureScore = @{ currentScore = 50; maxScore = 100; percentageCurrent = 50; percentageVsSimilar = 40; percentageVsAllTenants = 45; trend = @(@{ label = 'Sep 1'; value = 50 }) }
    Licenses = @(@{ name = 'E3'; used = '5'; available = '1'; total = '6' })
    Devices = @(@{ name = 'PC1'; os = 'Windows'; compliance = 'compliant'; compliant = $true; lastSync = 'Sep 1, 2026'; encrypted = $true })
    CAPolicies = @(@{ name = 'Require MFA'; state = 'enabled'; controls = @('mfa'); controlsText = 'MFA'; applications = 'All' })
    SecurityControls = @(@{ name = 'MFA'; description = 'd'; tags = 't'; status = 'Compliant' })
}
Save 'pester-executive' $r.Blocks $r.Variables $BrandMin -ReportName 'T'
$r = Build-CippBecReportTree -TenantName 'Contoso' -UserData @{ displayName = 'Alice'; userPrincipalName = 'alice@contoso.com' } -BecData @{
    ExtractedAt = '2026-09-01T00:00:00Z'; Score = @{ Value = 19; Level = 'High' }; NewRules = @(@{ Name = 'Hide'; MoveToFolder = 'RSS Subscriptions' })
    SentMessageAnalysis = @{ Flagged = $true; Bursts = @(@{ MessageCount = 40; RecipientCount = 40; WindowStart = '2026-09-01T09:00:00Z'; TopSubject = 'Invoice' }) }; LocationAnalysis = @{ UsageLocation = 'AU' }
}
Save 'pester-bec' $r.Blocks $r.Variables $BrandMin -ReportName 'T'

# Security Baseline with no data (the full report is sample-baseline, from ReportSamples/baseline.json)
$r = Build-CippBaselineWhatIfReportTree -Data @{ TenantName = 'Contoso' }
Save 'pester-baseline-empty' $r.Blocks $r.Variables $BrandMin -ReportName 'Baseline What-If'

# ================= (b) fixed reports: branding-preview samples (full branding, SVG logo on half) =================
$Names = @{ executive = 'Executive Summary'; reportBuilder = 'Quarterly Security Review'; shadowAI = 'Shadow AI Report'; bec = 'BEC Analysis Report'; becSummary = 'BEC Executive Summary'; sharing = 'Sharing Report'; permissions = 'Permissions Report'; mailFlow = 'Mail Flow Report'; licensing = 'Licensing Report'; baseline = 'Security Baseline Report' }
$i = 0
foreach ($Type in 'executive', 'reportBuilder', 'shadowAI', 'bec', 'becSummary', 'sharing', 'permissions', 'mailFlow', 'licensing', 'baseline') {
    $SampleType = if ($Type -eq 'becSummary') { 'bec' } else { $Type }
    $Sample = Get-Content "$Root/Config/ReportSamples/$SampleType.json" -Raw | ConvertFrom-Json -AsHashtable
    $Tenant = 'Contoso (sample data)'
    $Data = @{ TenantName = $Tenant } + $Sample
    $Report = switch ($Type) {
        'reportBuilder' { @{ Blocks = @($Sample.blocks); Variables = @{} } }
        'shadowAI' { Build-CippShadowAIReportTree -Data $Data }
        'bec' { Build-CippBecReportTree -UserData $Sample.userData -BecData $Sample.becData -TenantName $Tenant -Variant full }
        'becSummary' { Build-CippBecReportTree -UserData $Sample.userData -BecData $Sample.becData -TenantName $Tenant -Variant summary }
        'sharing' { Build-CippSharingReportTree -Data $Data }
        'permissions' { Build-CippPermissionsReportTree -Data $Data }
        'mailFlow' { Build-CippMailFlowReportTree -Data $Data }
        'licensing' { Build-CippLicenseReportTree -Data $Data }
        'baseline' { Build-CippBaselineWhatIfReportTree -Data $Data }
        default { Build-CippExecutiveReportTree -Data $Data }
    }
    $Brand = if ($i++ % 2) { $BrandSvg } else { $BrandFull }
    Save "sample-$Type" $Report.Blocks $Report.Variables $Brand -Tenant $Tenant -ReportName $Names[$Type]
}

# ================= perf: a heavy BEC (every list x40) =================
$Sample = Get-Content "$Root/Config/ReportSamples/bec.json" -Raw | ConvertFrom-Json -AsHashtable
$Big = @{}
foreach ($k in $Sample.becData.Keys) {
    $v = $Sample.becData[$k]
    $Big[$k] = if ($v -is [System.Collections.IList] -and $v.Count -gt 0) { @(foreach ($n in 1..40) { foreach ($item in $v) { $c = if ($item -is [System.Collections.IDictionary]) { $h = @{}; foreach ($kk in $item.Keys) { $h[$kk] = $item[$kk] }; $h } else { $item }; $c } }) } else { $v }
}
$r = Build-CippBecReportTree -UserData $Sample.userData -BecData $Big -TenantName 'Contoso' -Variant full
Save 'bec-large' $r.Blocks $r.Variables $BrandFull -ReportName 'BEC Analysis Report'

Get-ChildItem $Out | Select-Object Name, Length | Format-Table -AutoSize
