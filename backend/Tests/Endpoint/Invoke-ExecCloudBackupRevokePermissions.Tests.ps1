BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    function Invoke-List { param($Query) Invoke-ListCloudBackupUnusedPermissions -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupUnusedPermissions' -Query $Query) }
    function Invoke-Revoke { param($TenantId) Invoke-ExecCloudBackupRevokePermissions -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupRevokePermissions' -Body @{ TenantId = $TenantId }) }
    $script:OriginalApp = $env:ApplicationID
    $env:ApplicationID = 'app-1'
}
AfterAll { $env:ApplicationID = $script:OriginalApp }

Describe 'Cloud backup permission revoke' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:Records = @(
            [pscustomobject]@{ PartitionKey = 'GrantedRoles'; RowKey = 'c1'; RoleIds = '["75359482-378d-4052-8f01-80520e7db3cd"]'; GrantedAt = '2026-11-20T00:00:00.0000000Z' }
            [pscustomobject]@{ PartitionKey = 'GrantedRoles'; RowKey = 'c2'; RoleIds = '["75359482-378d-4052-8f01-80520e7db3cd","9492366f-7969-46a4-8d15-ed1a20078fff","59a6b24b-4225-4393-8165-ebaec5f55d7a"]'; GrantedAt = '2026-11-20T00:00:00.0000000Z' }
        )
        $script:BulkStatus = @{}
        $script:Requests = $null
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPAzDataTableEntity { New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"}]' } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "RowKey eq '([^']+)'") { $Key = $Matches[1]; return @($script:Records).Where({ $_.RowKey -eq $Key }) }
            $script:Records
        } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Get-CippSamPermissions { [pscustomobject]@{ Permissions = [pscustomobject]@{ '00000003-0000-0000-c000-000000000000' = [pscustomobject]@{ applicationPermissions = @([pscustomobject]@{ id = '59a6b24b-4225-4393-8165-ebaec5f55d7a'; value = 'Channel.ReadBasic.All' }) } } } }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'sp2' } } -ParameterFilter { $uri -like "*servicePrincipals(appId='app-1')*" }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'a1'; appRoleId = '75359482-378d-4052-8f01-80520e7db3cd' }
            [pscustomobject]@{ id = 'a2'; appRoleId = '9492366f-7969-46a4-8d15-ed1a20078fff' }
            [pscustomobject]@{ id = 'a3'; appRoleId = '59a6b24b-4225-4393-8165-ebaec5f55d7a' }
            [pscustomobject]@{ id = 'a4'; appRoleId = 'df021288-bdef-4463-88db-98f22de89214' }
        } -ParameterFilter { $uri -like '*/servicePrincipals/sp2/appRoleAssignments*' }
        Mock New-GraphBulkRequest {
            $script:Requests = $Requests
            foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = $script:BulkStatus[$Request.url] ?? 204 } }
        }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Clear-CippTokenCache { }
        Mock Write-LogMessage { }
    }

    It 'lists tenants no policy backs up, without the permissions in CIPP''s own set' {
        $Response = Invoke-List

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        $Rows.Count | Should -Be 1
        $Rows[0].TenantId | Should -Be 'c2'
        $Rows[0].Tenant | Should -Be 'fabrikam.com'
        $Rows[0].Permissions | Should -Be @('Files.ReadWrite.All', 'Sites.ReadWrite.All')
    }

    It 'lists only the selected tenant and only tenants the caller can access' {
        @((Invoke-List -Query @{ tenantFilter = 'contoso.com' }).Body).Count | Should -Be 0
        @((Invoke-List -Query @{ tenantFilter = 'fabrikam.com' }).Body.TenantId) | Should -Be @('c2')
        (Invoke-List -Query @{ tenantFilter = 'unknown.com' }).StatusCode | Should -Be 404
        $script:Allowed = @('c1')
        @((Invoke-List).Body).Count | Should -Be 0
    }

    It 'revokes only the roles cloud backup added that CIPP does not need, then forgets the tenant' {
        $Response = Invoke-Revoke -TenantId 'fabrikam.com'

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be 'Revoked 2 cloud backup permissions in fabrikam.com.'
        @($script:Requests.method | Select-Object -Unique) | Should -Be @('DELETE')
        @($script:Requests.url | Sort-Object) | Should -Be @('/servicePrincipals/sp2/appRoleAssignments/a1', '/servicePrincipals/sp2/appRoleAssignments/a2')
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupPermissions' -and $Entity.RowKey -eq 'c2' }
        Should -Invoke Clear-CippTokenCache -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'c2' }
    }

    It 'keeps the roles that could not be revoked so the revoke can be tried again' {
        $script:BulkStatus['/servicePrincipals/sp2/appRoleAssignments/a2'] = 403

        $Response = Invoke-Revoke -TenantId 'c2'

        $Response.StatusCode | Should -Be 207
        $Response.Body.Results | Should -BeLike '*Could not revoke: Sites.ReadWrite.All*'
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'c2' -and $Entity.RoleIds -eq '["9492366f-7969-46a4-8d15-ed1a20078fff"]' }
    }

    It 'refuses a tenant a policy still backs up, a tenant with nothing recorded, and bad input' {
        (Invoke-Revoke -TenantId 'contoso.com').StatusCode | Should -Be 400
        (Invoke-Revoke -TenantId 'tailspin.com').StatusCode | Should -Be 400
        (Invoke-Revoke -TenantId 'AllTenants').StatusCode | Should -Be 400
        (Invoke-Revoke -TenantId '').StatusCode | Should -Be 400
        (Invoke-Revoke -TenantId 'unknown.com').StatusCode | Should -Be 404
        $script:Allowed = @('c1')
        (Invoke-Revoke -TenantId 'fabrikam.com').StatusCode | Should -Be 403
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }
}
