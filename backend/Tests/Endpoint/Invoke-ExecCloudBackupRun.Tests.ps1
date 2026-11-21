BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    function Invoke-Run { param($Body) Invoke-ExecCloudBackupRun -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupRun' -Body $Body) }
}

Describe 'Invoke-ExecCloudBackupRun' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRows = @(New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"},{"type":"Tenant","customerId":"c2"}]')
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { @($script:CloudBackupTenants).Where({ $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }) }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRows } -ParameterFilter { $TableName -eq 'Config' }
        Mock Start-CloudBackupOrchestrator { 'run-1' }
        Mock Write-LogMessage { }
    }

    It 'returns 400 without a policy id' {
        (Invoke-Run -Body @{ PolicyId = 'nope' }).StatusCode | Should -Be 400
        Should -Invoke Start-CloudBackupOrchestrator -Times 0 -Exactly
    }

    It 'returns 404 for an unknown policy' {
        $script:PolicyRows = @()
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111' }).StatusCode | Should -Be 404
    }

    It 'starts the policy with -Force and accepts the request' {
        $Response = Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111' }

        $Response.StatusCode | Should -Be 202
        Should -Invoke Start-CloudBackupOrchestrator -Times 1 -Exactly -ParameterFilter { $PolicyId -eq '11111111-1111-1111-1111-111111111111' -and $Force -and -not $TenantFilter }
    }

    It 'passes a selected tenant through' {
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111'; tenantFilter = @{ value = 'fabrikam.com' } }).StatusCode | Should -Be 202
        Should -Invoke Start-CloudBackupOrchestrator -ParameterFilter { $TenantFilter -eq 'fabrikam.com' }
    }

    It 'passes a workload through and refuses one the policy does not back up' {
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111'; Workload = @{ value = 'OneDrive' } }).StatusCode | Should -Be 202
        Should -Invoke Start-CloudBackupOrchestrator -Times 1 -Exactly -ParameterFilter { $Workload -eq 'onedrive' }

        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111'; Workload = 'teams' }).StatusCode | Should -Be 400
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111'; Workload = 'config' }).StatusCode | Should -Be 400
        Should -Invoke Start-CloudBackupOrchestrator -Times 1 -Exactly
    }

    It 'returns 400 when there is nothing to back up and 500 when the orchestrator failed' {
        Mock Start-CloudBackupOrchestrator { 0 }
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111' }).StatusCode | Should -Be 400
        Mock Start-CloudBackupOrchestrator { $false }
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111' }).StatusCode | Should -Be 500
    }

    It 'returns 403 to a restricted caller for a policy reaching other tenants, unless they run only their own tenant' {
        $script:Allowed = @('c1')

        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111' }).StatusCode | Should -Be 403
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111'; tenantFilter = 'fabrikam.com' }).StatusCode | Should -Be 403
        (Invoke-Run -Body @{ PolicyId = '11111111-1111-1111-1111-111111111111'; tenantFilter = 'contoso.com' }).StatusCode | Should -Be 202
        Should -Invoke Start-CloudBackupOrchestrator -Times 1 -Exactly
    }
}
