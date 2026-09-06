# Pester tests for the fixed-report tree builders: each composes @{ Blocks; Variables } from shaped
# sample data, the grade on the cover matches the tree's own scoring, and the tree renders to a PDF.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'ConvertTo-CippReportPdf.ps1' | Select-Object -First 1 -ExpandProperty FullName)
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }

    function Test-Report($Report, [string]$Label) {
        $Report.Blocks.Count | Should -BeGreaterThan 0
        $Report.Variables.coverlabel | Should -Be $Label
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName 'Contoso' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }
}

Describe 'Report tree builders' {
    It 'Sharing: grades exposure from the summary and renders' {
        $r = Build-CippSharingReportTree -Data @{
            TenantName    = 'Contoso'
            summary       = @{ totalLinks = 4; itemsShared = 3; externalRecipients = 1; anonymousEditLinks = 1; neverExpiringAnonymous = 1 }
            links         = @(@{ fileName = 'a.docx'; siteName = 'S'; classification = 'Anonymous'; roles = @('write'); itemType = 'File' })
            topRecipients = @(@{ recipient = 'x@example.com'; links = 1 })
            topLibraries  = @()
        }
        $r.Variables.covermetanote | Should -Be 'Sharing exposure: High'
        Test-Report $r 'Data Sharing Review'
    }

    It 'Permissions: a lone detached library is Low exposure and renders' {
        $r = Build-CippPermissionsReportTree -Data @{
            TenantName  = 'Contoso'
            summary     = @{ uniquePermissionLibraries = 1; sitesScanned = 2; librariesScanned = 3; totalAssignments = 5 }
            assignments = @(@{ principalId = 'p1'; scope = 'Library'; siteName = 'S'; libraryTitle = 'Docs'; title = 'Bob'; permissionLevel = 'Edit'; principalType = 'User' })
        }
        $r.Variables.covermetanote | Should -Be 'Permission exposure: Low'
        Test-Report $r 'Access Review'
    }

    It 'MailFlow: sums the dispositions, grades hygiene and renders' {
        $r = Build-CippMailFlowReportTree -Data @{
            TenantName = 'Contoso'; days = 7
            totals     = @{ GoodMail = 90; EmailPhish = 10 }
            daily      = @(@{ date = '2026-09-01'; GoodMail = 90; EmailPhish = 10 })
            topSenders = @(@{ name = 'a@contoso.com'; count = 5 })
        }
        $r.Variables.covermeta | Should -Be '100 messages / 90% delivered / 10 threats caught'
        $r.Variables.covermetanote | Should -Be 'Mail hygiene: Attention Needed'
        Test-Report $r 'Email Traffic Review'
    }

    It 'MailFlow: an empty window (no rows at all) still renders, with empty charts' {
        $r = Build-CippMailFlowReportTree -Data @{ TenantName = 'Contoso' }
        $r.Variables.covermetanote | Should -Be 'Mail hygiene: Good'
        Test-Report $r 'Email Traffic Review'
    }

    It 'ShadowAI: merges sanctioned tools across both sources and renders' {
        $r = Build-CippShadowAIReportTree -Data @{
            TenantName    = 'Contoso'
            summary       = @{ aiToolsDetected = 2 }
            detectedApps  = @(@{ aiTool = 'ChatGPT'; vendor = 'OpenAI'; category = 'Chat'; status = 'Sanctioned'; deviceCount = 3; risk = 'High' })
            consentedApps = @(@{ aiTool = 'ChatGPT'; vendor = 'OpenAI'; category = 'Chat'; status = 'Sanctioned'; activeUsersLast7Days = 5; risk = 'High' })
            topTools      = @(); byRisk = @(@{ risk = 'High'; tools = 1 })
        }
        $Sanctioned = $r.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.rows[0].tool -eq 'ChatGPT' -and $_.rows[0].users } | Select-Object -First 1
        $Sanctioned.rows[0].devices | Should -Be '3'
        $Sanctioned.rows[0].users | Should -Be '5'
        Test-Report $r 'AI Risk Assessment'
    }

    It 'Executive: composes every section from shaped data and renders' {
        $r = Build-CippExecutiveReportTree -Data @{
            TenantName       = 'Contoso'
            UserStats        = @{ licensedUsers = 10; unlicensedUsers = 1; guests = 2; globalAdmins = 1; permanentGlobalAdmins = 1; eligibleGlobalAdmins = 0; pimCapable = $true }
            SecureScore      = @{ currentScore = 50; maxScore = 100; percentageCurrent = 50; percentageVsSimilar = 40; percentageVsAllTenants = 45; trend = @(@{ label = 'Sep 1'; value = 50 }) }
            Licenses         = @(@{ name = 'E3'; used = '5'; available = '1'; total = '6' })
            Devices          = @(@{ name = 'PC1'; os = 'Windows'; compliance = 'compliant'; compliant = $true; lastSync = 'Sep 1, 2026'; encrypted = $true })
            CAPolicies       = @(@{ name = 'Require MFA'; state = 'enabled'; controls = @('mfa'); controlsText = 'MFA'; applications = 'All' })
            SecurityControls = @(@{ name = 'MFA'; description = 'd'; tags = 't'; status = 'Compliant' })
        }
        @($r.Blocks | Where-Object { $_.type -eq 'hero' }).Count | Should -Be 5
        $r.Variables.covertenant | Should -Be 'Contoso'
        Test-Report $r 'SECURITY ASSESSMENT'
    }

    It 'BEC: scores the RSS-folder rule as High risk, names the user on the cover and renders' {
        $r = Build-CippBecReportTree -TenantName 'Contoso' -UserData @{ displayName = 'Alice'; userPrincipalName = 'alice@contoso.com' } -BecData @{
            ExtractedAt         = '2026-09-01T00:00:00Z'
            NewRules            = @(@{ Name = 'Hide'; MoveToFolder = 'RSS Subscriptions' })
            SentMessageAnalysis = @{ Flagged = $true; Bursts = @(@{ MessageCount = 40; RecipientCount = 40; WindowStart = '2026-09-01T09:00:00Z'; TopSubject = 'Invoice' }) }
            LocationAnalysis    = @{ UsageLocation = 'AU' }
        }
        ($r.Blocks | Where-Object { $_.type -eq 'alertbox' -and $_.title -like 'Threat Assessment:*' }).title | Should -Be 'Threat Assessment: High'
        $r.Variables.covertenant | Should -Be 'Alice'
        $r.Variables.footerlabel | Should -Be 'Contoso - BEC Analysis Report for Alice'
        Test-Report $r 'Security Incident Report'
    }
}
