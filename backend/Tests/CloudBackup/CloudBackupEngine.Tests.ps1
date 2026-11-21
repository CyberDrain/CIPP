BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
}

Describe 'Get-CIPPCloudBackupOwnerList' {
    BeforeEach {
        Mock Get-CIPPCloudBackupExchangeOwner {
            [pscustomobject]@{ OwnerId = 'u1'; OwnerType = 'UserMailbox'; DisplayName = 'Ann'; UserId = 'u1'; UserPrincipalName = 'ann@contoso.com'; SiteUrl = $null }
            [pscustomobject]@{ OwnerId = 'u2'; OwnerType = 'UserMailbox'; DisplayName = 'Bob'; UserId = 'u2'; UserPrincipalName = 'Bob@Contoso.com'; SiteUrl = $null }
            [pscustomobject]@{ OwnerId = 'u3'; OwnerType = 'SharedMailbox'; DisplayName = 'Info'; UserId = 'u3'; UserPrincipalName = 'info@contoso.com'; SiteUrl = $null }
            [pscustomobject]@{ OwnerId = 'u4'; OwnerType = 'UserMailbox'; DisplayName = 'Cy'; UserId = 'u4'; UserPrincipalName = 'cy@contoso.com'; SiteUrl = $null }
        }
        Mock Get-CIPPCloudBackupSharePointOwner {
            [pscustomobject]@{ OwnerId = 'contoso.sharepoint.com,a,b'; OwnerType = 'Site'; DisplayName = 'HR'; SiteUrl = 'https://contoso.sharepoint.com/sites/HR' }
            [pscustomobject]@{ OwnerId = 'contoso.sharepoint.com,c,d'; OwnerType = 'Site'; DisplayName = 'Sales'; SiteUrl = 'https://contoso.sharepoint.com/sites/sales' }
        }
        Mock Get-CIPPCloudBackupTeamsOwner {
            [pscustomobject]@{ OwnerId = 'g1'; OwnerType = 'Team'; DisplayName = 'Board' }
            [pscustomobject]@{ OwnerId = 'g2'; OwnerType = 'Team'; DisplayName = 'Staff' }
            [pscustomobject]@{ OwnerId = 'u1'; OwnerType = 'UserChats'; DisplayName = 'Ann'; UserId = 'u1'; UserPrincipalName = 'ann@contoso.com' }
        }
        Mock New-GraphBulkRequest { }
    }

    It 'returns every owner of the workload when nothing is excluded, without reading groups' {
        @(Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'exchange' -Exclusions $null).OwnerId | Should -Be @('u1', 'u2', 'u3', 'u4')
        Should -Invoke Get-CIPPCloudBackupExchangeOwner -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }

    It 'removes users excluded by id or by UPN in any case' {
        $Exclusions = [pscustomobject]@{ Users = @('u1', 'bob@contoso.com'); Groups = @(); Sites = @() }
        @(Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'exchange' -Exclusions $Exclusions).OwnerId | Should -Be @('u3', 'u4')
    }

    It 'removes transitive members of excluded groups with one batched read, ignoring groups that do not exist in the tenant' {
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = 'g1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u3'; userPrincipalName = 'info@contoso.com' }) } }
            [pscustomobject]@{ id = 'g1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u4' }) } }
            [pscustomobject]@{ id = 'g-other'; status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'not found' } } }
        }
        $Exclusions = [pscustomobject]@{ Users = @(); Groups = @('g1', 'g-other'); Sites = @() }

        @(Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'exchange' -Exclusions $Exclusions).OwnerId | Should -Be @('u1', 'u2')

        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.com' -and @($Requests).Count -eq 2 -and $Requests[0].url -like 'groups/*/transitiveMembers/microsoft.graph.user?*' -and $asapp -eq $true
        }
    }

    It 'throws when an excluded group cannot be read, rather than back up its members' {
        Mock New-GraphBulkRequest { [pscustomobject]@{ id = 'g1'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'denied' } } } }
        { Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'exchange' -Exclusions ([pscustomobject]@{ Groups = @('g1') }) } | Should -Throw '*g1*denied*'
    }

    It 'removes excluded sites by URL, ignoring case and a trailing slash' {
        $Exclusions = [pscustomobject]@{ Users = @(); Groups = @(); Sites = @('https://contoso.sharepoint.com/sites/hr/') }
        @(Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'sharepoint' -Exclusions $Exclusions).OwnerId | Should -Be @('contoso.sharepoint.com,c,d')
    }

    It 'removes an excluded group''s team and its members'' chats' {
        Mock New-GraphBulkRequest { [pscustomobject]@{ id = 'g1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u1' }) } } }
        $Exclusions = [pscustomobject]@{ Users = @(); Groups = @('g1'); Sites = @() }

        @(Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'teams' -Exclusions $Exclusions).OwnerId | Should -Be @('g2')
    }

    It 'refuses an unknown workload' {
        { Get-CIPPCloudBackupOwnerList -TenantFilter 'contoso.com' -Workload 'config' } | Should -Throw
    }
}

Describe 'Grant-CIPPCloudBackupPermission' {
    BeforeAll {
        $script:OriginalApp = $env:ApplicationID
        $script:OriginalTenant = $env:TenantID
        $env:ApplicationID = 'app-1'
        $env:TenantID = 'partner'
    }
    AfterAll {
        $env:ApplicationID = $script:OriginalApp
        $env:TenantID = $script:OriginalTenant
    }
    BeforeEach {
        $script:Requested = $null
        Mock Add-CIPPApplicationPermission { $script:Requested = $RequiredResourceAccess; 'Added 4 Application permissions to CIPP-SAM' }
        Mock Get-CIPPPartnerTenant { }
    }

    It 'asks for exactly the Graph application roles of the workloads: <Workloads>' -ForEach @(
        @{ Workloads = @('exchange'); Expected = @('089fe4d0-434a-44c5-8827-41ba8a0b17f5', '76577085-e73d-4f1d-b26a-85fb33892327', '798ee544-9d2d-430c-a058-570e29e34338', '7d9f353d-a7bd-4fbb-822a-26d5dd39a3ce', '99280d24-a782-4793-93cc-0888549957f6', 'e2a3a72e-5f79-4c64-b1b1-878b674786c9', 'fef87b92-8391-4589-9da7-eb93dab7dc8a') }
        @{ Workloads = @('onedrive', 'sharepoint'); Expected = @('75359482-378d-4052-8f01-80520e7db3cd', '9492366f-7969-46a4-8d15-ed1a20078fff') }
        @{ Workloads = @('teams'); Expected = @('2280dda6-0bfd-44ee-a2f4-cb867cfc4c1e', '59a6b24b-4225-4393-8165-ebaec5f55d7a', '6b7d71aa-70aa-4810-a8d9-5d9fb2830017', '7b2449af-6ccd-4f4d-9f78-e550c193f0d1') }
    ) {
        $Result = Grant-CIPPCloudBackupPermission -TenantFilter 'c1' -Workloads $Workloads

        $Result.Status | Should -Be 'Granted'
        $Result.CheckedAt | Should -Not -BeNullOrEmpty
        Should -Invoke Add-CIPPApplicationPermission -Times 1 -Exactly -ParameterFilter { $ApplicationId -eq 'app-1' -and $TenantFilter -eq 'c1' }
        @($script:Requested).Count | Should -Be 1
        $script:Requested[0].resourceAppId | Should -Be '00000003-0000-0000-c000-000000000000'
        @($script:Requested[0].resourceAccess.type | Select-Object -Unique) | Should -Be @('Role')
        @($script:Requested[0].resourceAccess.id | Sort-Object) | Should -Be $Expected
    }

    It 'reports Failed with the messages when a grant fails' {
        Mock Add-CIPPApplicationPermission { 'Added 1 Application permissions to CIPP-SAM'; 'Failed to grant x to y: Insufficient privileges' }

        $Result = Grant-CIPPCloudBackupPermission -TenantFilter 'c1' -Workloads @('teams')

        $Result.Status | Should -Be 'Failed'
        $Result.Message | Should -Be 'Failed to grant x to y: Insufficient privileges'
    }

    It 'reports Failed instead of throwing when the grant throws' {
        Mock Add-CIPPApplicationPermission { throw 'Service principal for application app-1 was not found in tenant c1' }

        $Result = Grant-CIPPCloudBackupPermission -TenantFilter 'c1' -Workloads @('teams')

        $Result.Status | Should -Be 'Failed'
        $Result.Message | Should -BeLike '*Service principal*'
    }

    It 'records only the roles it added, merged with those it added before' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'sp1' } } -ParameterFilter { $uri -like "*servicePrincipals(appId='app-1')*" }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ appRoleId = '6b7d71aa-70aa-4810-a8d9-5d9fb2830017' }
            [pscustomobject]@{ appRoleId = '2280dda6-0bfd-44ee-a2f4-cb867cfc4c1e' }
        } -ParameterFilter { $uri -like '*/servicePrincipals/sp1/appRoleAssignments*' }
        Mock Add-CIPPApplicationPermission { 'Added 1 Application permissions to CIPP-SAM'; 'Failed to grant 7b2449af-6ccd-4f4d-9f78-e550c193f0d1 to y: Insufficient privileges' }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'GrantedRoles'; RowKey = 'c1'; RoleIds = '["75359482-378d-4052-8f01-80520e7db3cd"]' } } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        $script:Recorded = $null
        Mock Add-CIPPAzDataTableEntity { $script:Recorded = $Entity } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }

        $Result = Grant-CIPPCloudBackupPermission -TenantFilter 'c1' -Workloads @('teams')

        $Result.Status | Should -Be 'Failed'
        $script:Recorded.PartitionKey | Should -Be 'GrantedRoles'
        $script:Recorded.RowKey | Should -Be 'c1'
        @([CIPP.CippJson]::ConvertFromJson($script:Recorded.RoleIds) | Sort-Object) | Should -Be @('59a6b24b-4225-4393-8165-ebaec5f55d7a', '75359482-378d-4052-8f01-80520e7db3cd')
    }

    It 'records nothing when it cannot read the roles the app already has' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        Mock Add-CIPPAzDataTableEntity { } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }

        (Grant-CIPPCloudBackupPermission -TenantFilter 'c1' -Workloads @('teams')).Status | Should -Be 'Granted'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
    }

    It 'never grants in a partner tenant, where Add-CIPPApplicationPermission would apply the CIPP defaults instead' {
        (Grant-CIPPCloudBackupPermission -TenantFilter 'partner' -Workloads @('exchange')).Status | Should -Be 'Failed'
        Mock Get-CIPPPartnerTenant { [pscustomobject]@{ TenantId = 'p2' } }
        (Grant-CIPPCloudBackupPermission -TenantFilter 'p2' -Workloads @('exchange')).Status | Should -Be 'Failed'
        Should -Invoke Add-CIPPApplicationPermission -Times 0 -Exactly
    }
}

Describe 'Write-CIPPCloudBackupItem and Remove-CIPPCloudBackupItem' {
    BeforeEach {
        $script:Sent = $null
        $script:Context = [pscustomobject]@{ Destination = [pscustomobject]@{ Provider = 'S3' }; OwnerPrefix = 'p/c1/onedrive/u1/'; KeyId = $null; Key = $null }
        Mock Send-CIPPCloudBackupObjectStream {
            $Copy = [System.IO.MemoryStream]::new()
            $Stream.CopyTo($Copy)
            $script:Sent = [pscustomobject]@{ Key = $Key; Bytes = $Copy.ToArray(); ContentType = $ContentType; Metadata = $Metadata; KeyId = $KeyId; EncryptionKey = $EncryptionKey; Bound = @($PesterBoundParameters.Keys) }
            [pscustomobject]@{ Key = $Key; Bytes = $Copy.Length; VersionId = 'v9' }
        }
        Mock Remove-CIPPCloudBackupObject { }
    }

    It 'streams a byte body under the owner prefix and returns the storage result' {
        $Result = Write-CIPPCloudBackupItem -Context $script:Context -ItemKey '/items/d1/i1' -Body ([byte[]](7, 8, 9)) -ContentType 'text/plain' -Metadata @{ name = 'a.txt' }

        $Result.Key | Should -Be 'p/c1/onedrive/u1/items/d1/i1'
        $Result.VersionId | Should -Be 'v9'
        $script:Sent.Bytes | Should -Be @(7, 8, 9)
        $script:Sent.ContentType | Should -Be 'text/plain'
        $script:Sent.Metadata.name | Should -Be 'a.txt'
        $script:Sent.Bound | Should -Contain 'ContentType'
        $script:Sent.Bound | Should -Not -Contain 'KeyId'
        $script:Sent.Bound | Should -Not -Contain 'EncryptionKey'
    }

    It 'passes a stream through without buffering it first' {
        $Source = [System.IO.MemoryStream]::new([byte[]](1, 2))
        Write-CIPPCloudBackupItem -Context $script:Context -ItemKey 'items/d1/i2' -Stream $Source | Out-Null

        Should -Invoke Send-CIPPCloudBackupObjectStream -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Stream, $Source) -and $ContentType -eq 'application/octet-stream' }
    }

    It 'asks the storage layer to encrypt with the policy key' {
        $script:Context.KeyId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $script:Context.Key = [byte[]]::new(32)

        Write-CIPPCloudBackupItem -Context $script:Context -ItemKey 'items/d1/i1' -Body ([byte[]](1)) | Out-Null

        $script:Sent.KeyId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $script:Sent.EncryptionKey.Length | Should -Be 32
        $script:Sent.Key | Should -Be 'p/c1/onedrive/u1/items/d1/i1'
    }

    It 'removes an item under the owner prefix' {
        Remove-CIPPCloudBackupItem -Context $script:Context -ItemKey 'items/d1/i1'
        Should -Invoke Remove-CIPPCloudBackupObject -Times 1 -Exactly -ParameterFilter { $Key -eq 'p/c1/onedrive/u1/items/d1/i1' -and $Destination.Provider -eq 'S3' }
    }
}
