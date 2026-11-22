# Pester tests for Invoke-ExecGetStorageReportPdf: the large file scan and the SharePoint tenant settings are
# optional sections, so failing to read either one still exports the report without that section.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
        [object]$ContentType
        [object]$Headers
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippReportTenantName { param($TenantFilter, $BrandingPresetId) 'Contoso' }
    function ConvertTo-CippReportPdf { param($Blocks, $Variables, $TenantName, $TenantFilter, $ReportName, $BrandingPresetId) [byte[]]@(37, 80, 68, 70, 45) }
    function Get-CIPPSharePointSiteUsageReport { [CmdletBinding()] param($TenantFilter) @() }
    function Get-CIPPOneDriveUsageReport { [CmdletBinding()] param($TenantFilter) @() }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $TableName) }
    function Build-CippStorageReportTree { param($Data) @{ Blocks = @(); Variables = @{} } }
    function Get-CippException { param($Exception) @{ NormalizedError = [string]$Exception } }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecGetStorageReportPdf.ps1')
}

Describe 'Invoke-ExecGetStorageReportPdf' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Build-CippStorageReportTree { @{ Blocks = @(); Variables = @{} } }
    }

    It 'exports without the <Section> when it cannot be read' -ForEach @(
        @{ Section = 'large files'; Failing = 'StorageLargeFiles'; Missing = 'largeFiles'; Kept = 'archive' }
        @{ Section = 'tenant archive settings'; Failing = 'SPOTenant'; Missing = 'archive'; Kept = 'largeFiles' }
    ) {
        $Fail = $Failing
        Mock New-CIPPDbRequest {
            if ($Type -eq $Fail) { throw 'The table service is unavailable.' }
            switch ($Type) {
                'StorageLargeFiles' { [pscustomobject]@{ rowType = 'File'; name = 'a.mov' } }
                'SPOTenant' { [pscustomobject]@{ EnableSiteArchive = $true } }
            }
        }

        $Response = Invoke-ExecGetStorageReportPdf -Request @{ Query = @{ tenantFilter = 'contoso.onmicrosoft.com' }; Body = @{}; Headers = @{} } -TriggerMetadata @{ FunctionName = 'ExecGetStorageReportPdf' }

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.ContentType | Should -Be 'application/pdf'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' }
        Should -Invoke Build-CippStorageReportTree -Times 1 -Exactly -ParameterFilter { -not $Data[$Missing] -and $Data[$Kept] }
    }
}
