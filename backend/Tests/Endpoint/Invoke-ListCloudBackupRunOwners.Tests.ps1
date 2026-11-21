BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    $script:RunId = '11111111-1111-1111-1111-111111111111_0000000000000000001_c1_sharepoint'
    function Invoke-Owners { param($Query) Invoke-ListCloudBackupRunOwners -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupRunOwners' -Query $Query) }
}

Describe 'Invoke-ListCloudBackupRunOwners' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:RunRow = New-CloudBackupRunRow -RowKey '0000000000000000001_c1_sharepoint' -Workload 'sharepoint'
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-CIPPAzDataTableEntity { $script:RunRow } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{
                PartitionKey = $script:RunId; RowKey = 'contoso.sharepoint.com,a1,b2'; OwnerId = 'contoso.sharepoint.com,a1,b2'; OwnerType = 'Site'; DisplayName = 'HR'; SiteUrl = 'https://contoso.sharepoint.com/sites/hr'
                Status = 'PartialSuccess'; Items = 4; Bytes = 4096; Deleted = 1; WarningCount = 2; Warnings = '["a.docx: locked","b.docx: locked"]'; Error = ''
                StartedAt = '2026-11-19T00:00:00.0000000Z'; CompletedAt = '2026-11-19T00:01:00.0000000Z'
            }
        } -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' }
        Mock Write-LogMessage { }
    }

    It 'returns the per-owner results of the run' {
        $Response = Invoke-Owners -Query @{ RunId = $script:RunId }

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        $Rows.Count | Should -Be 1
        $Rows[0].OwnerId | Should -Be 'contoso.sharepoint.com,a1,b2'
        $Rows[0].OwnerType | Should -Be 'Site'
        $Rows[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/hr'
        $Rows[0].UserPrincipalName | Should -BeNullOrEmpty
        $Rows[0].Status | Should -Be 'PartialSuccess'
        $Rows[0].Bytes | Should -Be 4096
        $Rows[0].Deleted | Should -Be 1
        @($Rows[0].Warnings) | Should -Be @('a.docx: locked', 'b.docx: locked')
        $Rows[0].Error | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupRuns' -and $Filter -eq "PartitionKey eq '11111111-1111-1111-1111-111111111111' and RowKey eq '0000000000000000001_c1_sharepoint'" }
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' -and $Filter -eq "PartitionKey eq '$($script:RunId)'" }
    }

    It 'returns 400 for a missing or malformed run id: <RunId>' -ForEach @(
        @{ RunId = '' }, @{ RunId = 'x' }, @{ RunId = "11111111-1111-1111-1111-111111111111_0000000000000000001_c1' or 1 eq 1" }
    ) {
        (Invoke-Owners -Query @{ RunId = $RunId }).StatusCode | Should -Be 400
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'returns 404 for an unknown run' {
        $script:RunRow = $null
        (Invoke-Owners -Query @{ RunId = $script:RunId }).StatusCode | Should -Be 404
    }

    It 'returns 403 to a caller without access to the run tenant' {
        $script:Allowed = @('c2')
        (Invoke-Owners -Query @{ RunId = $script:RunId }).StatusCode | Should -Be 403
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' }
    }

    It 'returns 500 when the table read fails' {
        Mock Get-CIPPAzDataTableEntity { throw 'table down' } -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' }
        (Invoke-Owners -Query @{ RunId = $script:RunId }).StatusCode | Should -Be 500
    }
}
