# Pester tests for the PDF path of Push-ExecGenerateReportBuilderReport: a rendered PDF is stored on
# the entity, attached to the scheduled-email envelope, and -PreviewOnly returns bytes without storing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Core.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'OfficeIMO.Pdf.dll'))
    [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin 'CIPPSharp.dll'))

    function Find-Module1([string]$Name) {
        Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    . (Find-Module1 'ConvertTo-CippReportPdf.ps1')
    . (Find-Module1 'Push-ExecGenerateReportBuilderReport.ps1')

    # Static stubs for the storage/data helpers the generator calls. The Add stub captures the stored
    # entity so the test can assert on the PDF it wrote. No pass-through mocks.
    $script:StoredEntity = $null
    function Get-CippTable { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @{} }
    function Get-CIPPAzDataTableEntity { param([switch]$Force, [Parameter(ValueFromRemainingArguments = $true)]$Rest) @() }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force, [Parameter(ValueFromRemainingArguments = $true)]$Rest) $script:StoredEntity = $Entity }
    function Get-CIPPBrandingSettings { @{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) $null }
    function Get-Tenants { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) @{ displayName = 'Contoso' } }
    function Write-LogMessage { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception)" } }

    $script:Blocks = ConvertTo-Json -InputObject @(@{ type = 'blank'; title = 'Summary'; content = '<p>Hello</p>' }) -Depth 10
}

Describe 'Push-ExecGenerateReportBuilderReport PDF path' {
    It 'stores a base64 PDF on the report entity' {
        $script:StoredEntity = $null
        $null = Push-ExecGenerateReportBuilderReport -TenantFilter 'contoso.onmicrosoft.com' -TemplateName 'Test Report' -Blocks $script:Blocks
        $script:StoredEntity | Should -Not -BeNullOrEmpty
        $script:StoredEntity.Pdf | Should -Not -BeNullOrEmpty
        $script:StoredEntity.PdfContentType | Should -Be 'application/pdf'
        # The stored value must be valid base64 of a real PDF.
        $bytes = [Convert]::FromBase64String($script:StoredEntity.Pdf)
        [System.Text.Encoding]::ASCII.GetString($bytes[0..4]) | Should -Be '%PDF-'
    }

    It 'returns the rendered PDF as an application/pdf task attachment' {
        $result = Push-ExecGenerateReportBuilderReport -TenantFilter 'contoso.onmicrosoft.com' -TemplateName 'Test Report' -Blocks $script:Blocks
        $result.TaskAttachments | Should -Not -BeNullOrEmpty
        @($result.TaskAttachments | Where-Object { $_.ContentType -eq 'application/pdf' }).Count | Should -Be 1
    }

    It 'PreviewOnly returns bytes without persisting a report row' {
        $script:StoredEntity = $null
        $result = Push-ExecGenerateReportBuilderReport -TenantFilter 'contoso.onmicrosoft.com' -Blocks $script:Blocks -PreviewOnly
        $result.PdfBase64 | Should -Not -BeNullOrEmpty
        $script:StoredEntity | Should -BeNullOrEmpty
    }
}
