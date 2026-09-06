# Pester tests for the Baseline What-If report: the tree builder puts the right standards in the
# right sections with the wording the client document used, and the endpoint renders the tree from
# the alignment getters into PDF bytes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    $null = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])

    $Reporting = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1
    Get-ChildItem -Path $Reporting.FullName -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    foreach ($Name in 'ConvertTo-CippReportPdf.ps1', 'Invoke-ExecGetBaselineWhatIfReportPdf.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name | Select-Object -First 1 -ExpandProperty FullName)
    }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) @() }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    $script:Catalog = @(
        @{ name = 'MFA'; label = 'Require MFA'; executiveText = 'Everyone signs in with a second factor.' }
        @{ name = 'Legacy'; label = 'Block legacy auth'; executiveText = 'Old sign-in protocols are switched off.' }
        @{ name = 'CA'; label = 'Conditional Access'; executiveText = 'Access rules follow the device and location.' }
        @{ name = 'Guests'; label = 'Disable stale guests'; executiveText = 'Guests who stop signing in are disabled.' }
    )
    $script:Alignment = [PSCustomObject]@{
        summary     = @{ alignedPercentage = 75; verifiedPercentage = 50 }
        rows        = @(
            @{ standardName = 'Legacy'; standardLabel = 'Block legacy auth'; status = 'Drift'; impact = 'High Impact'; secureScoreImpact = 5; sourceTemplate = 'Core' }
            @{ standardName = 'MFA'; standardLabel = 'Require MFA'; status = 'Compliant'; impact = 'Low Impact'; secureScoreImpact = 0; sourceTemplate = 'Core' }
            @{ standardName = 'Guests'; standardLabel = 'Disable stale guests'; status = 'Accepted'; deviationReason = 'Guests are reviewed by HR quarterly.'; sourceTemplate = 'Core' }
            @{ standardName = 'CA'; standardLabel = 'Conditional Access'; status = 'Denied - Remediate Pending'; impact = 'Medium Impact'; secureScoreImpact = 0; sourceTemplate = 'Core' }
        )
        stageStates = @(
            @{
                templateId = 'core'; templateName = 'Core'; currentStage = 1; totalStages = 2; stageName = 'Foundations'
                enteredStageAt = '2026-09-01T00:00:00Z'; nextStageName = 'Hardening'
                nextStage      = @{ name = 'Hardening'; logic = 'and'; conditions = @(@{ type = 'time'; days = 2; unit = 'weeks' }, @{ type = 'success' }); standards = @('CA', 'CA#2', 'Unknown') }
            }
        )
    }
    $script:Simulated = @{
        GUID = 'sim'; templateName = 'Security Plus'; description = 'Adds the extras'
        stages = @(
            @{ name = 'Kickoff'; standards = @('MFA#1', 'Legacy') }
            @{ name = 'Later'; logic = 'or'; conditions = @(@{ type = 'manual' }, @{ type = 'variable'; variable = 'tier'; operator = 'eq'; value = 'gold' }); standards = @('Guests') }
        )
    }
    function Build-Fixture([switch]$WithSimulation) {
        Build-CippBaselineWhatIfReportTree -Data @{
            TenantName = 'Contoso'; TenantFilter = 'contoso.onmicrosoft.com'
            summary = $script:Alignment.summary; rows = $script:Alignment.rows; stageStates = $script:Alignment.stageStates
            simulatedTemplate = $(if ($WithSimulation) { $script:Simulated }); catalog = $script:Catalog
        }
    }
    function Get-BlockText($Report) { $Report.Blocks | ConvertTo-Json -Depth 10 -Compress }
}

Describe 'Build-CippBaselineWhatIfReportTree' {
    It 'counts the changes, planned stages and exceptions onto the cover' {
        $r = Build-Fixture
        $r.Variables.coverlabel | Should -Be 'Baseline What-If'
        $r.Variables.covermeta | Should -Be '2 changes to make / 1 staged rollout / 1 agreed exception'
        $r.Variables.covermetanote | Should -Be 'Compliant with baseline: 50%'
    }

    It 'lists the drifted and denied standards as changes, with their impact notes' {
        $text = Get-BlockText (Build-Fixture)
        $text | Should -Match 'Changes we would make now \(2\)'
        $text | Should -Match 'Old sign-in protocols are switched off\. \(High Impact - increases Secure Score by up to 5 points\)'
        $text | Should -Match 'Access rules follow the device and location\. \(Medium Impact - deviation denied, fix pending\)'
        $text | Should -Match 'Guests are reviewed by HR quarterly\.'
    }

    It 'describes the next stage in words with an estimated date, listing only catalogued standards once' {
        $text = Get-BlockText (Build-Fixture)
        $text | Should -Match 'Currently in Stage 1 of 2 \(Foundations\)\. Next: Stage 2 \(Hardening\) - advances when 2 weeks in the previous stage AND all previous stage items applied successfully, estimated around September 15, 2026\.'
        ([regex]::Matches($text, 'Access rules follow the device and location\. ')).Count | Should -Be 1
        $text | Should -Not -Match 'Unknown'
    }

    It 'adds the what-if section only when a baseline is simulated, marking what is already aligned' {
        (Get-BlockText (Build-Fixture)) | Should -Not -Match 'What-if: assigning'
        $text = Get-BlockText (Build-Fixture -WithSimulation)
        $text | Should -Match 'What-if: assigning the Security Plus baseline'
        $text | Should -Match 'Stage 1: Kickoff - applies immediately'
        $text | Should -Match 'Everyone signs in with a second factor\. No change - already aligned today \(configured by Core\)\.'
        $text | Should -Match 'Old sign-in protocols are switched off\. Would change this tenant when the stage applies\.'
        $text | Should -Match "Stage 2: Later - advances when manual approval by an operator OR tier equals 'gold'"
    }

    It 'renders an empty tenant with the nothing-to-change notes' {
        $r = Build-CippBaselineWhatIfReportTree -Data @{ TenantName = 'Contoso' }
        $text = Get-BlockText $r
        $text | Should -Match 'Nothing to change'
        $text | Should -Match 'No further staged changes'
        $Bytes = ConvertTo-CippReportPdf -Blocks $r.Blocks -Variables $r.Variables -TenantName 'Contoso' -ReportName 'T'
        [System.Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }
}

Describe 'Invoke-ExecGetBaselineWhatIfReportPdf' {
    BeforeAll {
        function Get-Tenants { param($TenantFilter) @{ displayName = 'Contoso' } }
        function Get-CIPPBaselineAlignment { param($TenantFilter) $script:Alignment }
        function Get-CIPPBaseline { @($script:Simulated, @{ GUID = 'core'; templateName = 'Core'; stages = @() }) }
        function Get-CIPPBaselineDefinition { $script:Catalog }
        function Invoke-Report($Body) {
            Invoke-ExecGetBaselineWhatIfReportPdf -Request @{ Body = $Body; Query = @{}; Headers = @{} } -TriggerMetadata @{ FunctionName = 'ExecGetBaselineWhatIfReportPdf' }
        }
    }

    It 'renders the tenant alignment, with a simulated baseline, as a PDF' {
        $Response = Invoke-Report @{ tenantFilter = 'contoso.onmicrosoft.com'; simulatedTemplateId = 'sim' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        $Response.Headers.'Content-Disposition' | Should -Be 'inline; filename="Baseline_WhatIf_Report_contoso_onmicrosoft_com.pdf"'
        [System.Text.Encoding]::ASCII.GetString($Response.Body[0..4]) | Should -Be '%PDF-'
    }

    It 'requires a tenantFilter' {
        (Invoke-Report @{}).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}
