BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')

    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    $script:DestId = '22222222-2222-2222-2222-222222222222'
    function New-PolicyBody {
        param([hashtable]$Overrides = @{})
        $Body = @{
            Action         = 'Add'
            Name           = 'Nightly'
            Enabled        = $true
            DestinationId  = @{ label = 'Blob'; value = $script:DestId }
            Tenants        = @(
                [pscustomobject]@{ label = 'Contoso (contoso.com)'; value = 'contoso.com'; type = 'Tenant'; addedFields = [pscustomobject]@{ customerId = 'c1'; defaultDomainName = 'contoso.com'; displayName = 'Contoso' } }
                [pscustomobject]@{ label = 'Fabrikam (fabrikam.com)'; value = 'fabrikam.com'; type = 'Tenant' }
            )
            Workloads      = @(@{ label = 'Exchange'; value = 'exchange' }, 'OneDrive')
            Schedules      = @{ exchange = @{ label = 'Every 12 hours'; value = '12h' } }
            Exclusions     = @{ Users = @(@{ label = 'Ann'; value = 'u1' }, 'bob@contoso.com'); Groups = @(@{ label = 'Board'; value = 'g9' }); Sites = @('https://contoso.sharepoint.com/sites/hr/') }
            RetentionDays  = 30
            Encryption     = $false
        }
        foreach ($Key in $Overrides.Keys) { $Body[$Key] = $Overrides[$Key] }
        $Body
    }
    function Invoke-Policy { param($Body) Invoke-ExecCloudBackupPolicy -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupPolicy' -Body $Body) }
}

Describe 'Invoke-ExecCloudBackupPolicy' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRows = @()
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Order = [System.Collections.Generic.List[string]]::new()
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        $script:PermissionRows = @()
        $script:PermissionWrites = [System.Collections.Generic.List[object]]::new()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRows } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:PermissionRows } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Entity = $Entity; OperationType = $OperationType }); $script:Order.Add('save') } -ParameterFilter { $TableName -eq 'Config' }
        Mock Add-CIPPAzDataTableEntity { foreach ($Row in @($Entity)) { $script:PermissionWrites.Add($Row) } } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $Id; Name = 'Blob'; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupVersioning { 'Enabled' }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Set-CIPPCloudBackupRetentionRule { $script:Order.Add('rule') }
        Mock Remove-CIPPCloudBackupRetentionRule { }
        Mock New-CIPPCloudBackupKey { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
        Mock Write-LogMessage { }
    }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'an unknown action'; Overrides = @{ Action = 'Nope' } }
        @{ Case = 'Edit without an id'; Overrides = @{ Action = 'Edit' } }
        @{ Case = 'a missing name'; Overrides = @{ Name = ' ' } }
        @{ Case = 'a missing destination'; Overrides = @{ DestinationId = $null } }
        @{ Case = 'no tenants'; Overrides = @{ Tenants = @() } }
        @{ Case = 'no workloads'; Overrides = @{ Workloads = @() } }
        @{ Case = 'an unknown workload'; Overrides = @{ Workloads = @('ConditionalAccess') } }
        @{ Case = 'an unknown schedule'; Overrides = @{ Schedules = @{ exchange = '2h' } } }
        @{ Case = 'a 4h OneDrive schedule'; Overrides = @{ Schedules = @{ onedrive = '4h' } } }
        @{ Case = 'a 4h SharePoint schedule'; Overrides = @{ Workloads = @('sharepoint'); Schedules = @{ sharepoint = @{ value = '4h' } } } }
        @{ Case = 'an excluded site that is not a URL'; Overrides = @{ Exclusions = @{ Sites = @('hr') } } }
        @{ Case = 'retention below 7 days'; Overrides = @{ RetentionDays = 6 } }
        @{ Case = 'retention above 3650 days'; Overrides = @{ RetentionDays = 3651 } }
        @{ Case = 'retention that is not a number'; Overrides = @{ RetentionDays = 'abc' } }
    ) {
        (Invoke-Policy -Body (New-PolicyBody -Overrides $Overrides)).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 0 -Exactly
    }

    It 'returns 400 when the destination does not exist' {
        Mock Get-CIPPCloudBackupDestination { }

        (Invoke-Policy -Body (New-PolicyBody)).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'returns 400 and saves nothing when versioning is not enabled on the destination: <Versioning>' -ForEach @(
        @{ Versioning = 'Suspended' }, @{ Versioning = 'Disabled' }, @{ Versioning = $null }
    ) {
        Mock Get-CIPPCloudBackupVersioning { $Versioning }

        $Response = Invoke-Policy -Body (New-PolicyBody)

        $Response.StatusCode | Should -Be 400
        "$($Response.Body.Results)" | Should -BeLike '*versioning*'
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'refuses a retention shorter than the immutability period of the destination' {
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $Id; Name = 'Blob'; Provider = 'AzureBlob'; ImmutabilityDays = 60 } }

        $Response = Invoke-Policy -Body (New-PolicyBody -Overrides @{ RetentionDays = 30 })

        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*at least 60*'
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 0 -Exactly
        $script:Writes.Count | Should -Be 0

        (Invoke-Policy -Body (New-PolicyBody -Overrides @{ RetentionDays = 60 })).StatusCode | Should -Be 200
    }

    It 'returns 500 when the versioning status cannot be read' {
        Mock Get-CIPPCloudBackupVersioning { throw 'AuthorizationFailed' }

        (Invoke-Policy -Body (New-PolicyBody)).StatusCode | Should -Be 500
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'adds a policy: sets the versioned retention rule first, stores customerIds, workloads, schedules, exclusions and next runs' {
        $Response = Invoke-Policy -Body (New-PolicyBody)

        $Response.StatusCode | Should -Be 200
        @($script:Order) | Should -Be @('rule', 'save')
        $Saved = $script:Writes[0].Entity
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 1 -Exactly -ParameterFilter { $RuleName -eq "cipp-$($Saved.RowKey)" -and $Prefix -eq "$($Saved.RowKey)/" -and $Days -eq 30 -and $Mode -eq 'Versioned' }
        $Saved.PartitionKey | Should -Be 'CloudBackupPolicy'
        $Saved.DestinationId | Should -Be $script:DestId
        $Tenants = $Saved.Tenants | ConvertFrom-Json
        @($Tenants.type) | Should -Be @('Tenant', 'Tenant')
        @($Tenants.customerId) | Should -Be @('c1', 'c2')
        @($Saved.Workloads | ConvertFrom-Json) | Should -Be @('exchange', 'onedrive')
        $Saved.Schedules | Should -Be '{"exchange":"12h","onedrive":"6h"}'
        $Saved.Exclusions | Should -Be '{"Users":["u1","bob@contoso.com"],"Groups":["g9"],"Sites":["https://contoso.sharepoint.com/sites/hr"]}'
        $Saved.RetentionDays | Should -Be 30
        $NextRuns = @{}
        foreach ($Match in [regex]::Matches($Saved.NextRuns, '"(\w+)":"([^"]+)"')) { $NextRuns[$Match.Groups[1].Value] = $Match.Groups[2].Value }
        @($NextRuns.Keys | Sort-Object) | Should -Be @('exchange', 'onedrive')
        foreach ($Value in $NextRuns.Values) { ([datetimeoffset]::Parse($Value).UtcDateTime - [datetime]::UtcNow).Duration().TotalMinutes | Should -BeLessThan 1 }
        $Saved.PSObject.Properties['ConfigAreas'] | Should -BeNullOrEmpty
        $Saved.CurrentKeyId | Should -Be ''
        Should -Invoke New-CIPPCloudBackupKey -Times 0 -Exactly
    }

    It 'stores All Tenants and tenant groups from the selector' {
        $Body = New-PolicyBody -Overrides @{ Tenants = @(
                [pscustomobject]@{ label = '*All Tenants (AllTenants)'; value = 'AllTenants'; type = 'Tenant'; addedFields = [pscustomobject]@{ defaultDomainName = 'AllTenants'; displayName = '*All Tenants'; customerId = 'AllTenants' } }
                [pscustomobject]@{ label = 'EU customers'; value = 'g1'; type = 'Group' }
            )
        }

        (Invoke-Policy -Body $Body).StatusCode | Should -Be 200

        $Saved = $script:Writes[0].Entity.Tenants
        $Saved | Should -Be '[{"type":"AllTenants"},{"type":"Group","id":"g1"}]'
    }

    It 'returns 400 for a tenant that cannot be resolved' {
        $Body = New-PolicyBody -Overrides @{ Tenants = @([pscustomobject]@{ label = 'Gone'; value = 'gone.com'; type = 'Tenant' }) }

        (Invoke-Policy -Body $Body).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'does not save when the retention rule cannot be set, and returns its status' -ForEach @(
        @{ Error = { throw 'AuthorizationFailed' }; Expected = 500 }
        @{ Error = { throw [System.Management.Automation.ItemNotFoundException]::new('NoSuchBucket') }; Expected = 404 }
        @{ Error = { throw [System.ArgumentException]::new('bad config') }; Expected = 400 }
    ) {
        Mock Set-CIPPCloudBackupRetentionRule $Error

        $Response = Invoke-Policy -Body (New-PolicyBody)

        $Response.StatusCode | Should -Be $Expected
        "$($Response.Body.Results)" | Should -BeLike 'Policy not saved*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'creates a key when encryption is turned on without one' {
        (Invoke-Policy -Body (New-PolicyBody -Overrides @{ Encryption = $true })).StatusCode | Should -Be 200

        $Saved = $script:Writes[0].Entity
        $Saved.Encryption | Should -BeTrue
        $Saved.CurrentKeyId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        @($Saved.KeyIds | ConvertFrom-Json) | Should -Be @('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    }

    It 'keeps the existing key and next run on Edit, and moves the rule when the destination changes' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow -Encryption $true -CurrentKeyId 'k1' -KeyIds '["k1"]' -NextRuns '{"exchange":"2026-12-01T00:00:00.0000000Z","teams":"2026-12-02T00:00:00.0000000Z"}')
        $NewDest = '77777777-7777-7777-7777-777777777777'

        $Response = Invoke-Policy -Body (New-PolicyBody -Overrides @{ Action = 'Edit'; Id = $script:PolicyId; Encryption = $true; DestinationId = $NewDest })

        $Response.StatusCode | Should -Be 200
        $Saved = $script:Writes[0].Entity
        $Saved.RowKey | Should -Be $script:PolicyId
        $Saved.CurrentKeyId | Should -Be 'k1'
        $NextRuns = @{}
        foreach ($Match in [regex]::Matches($Saved.NextRuns, '"(\w+)":"([^"]+)"')) { $NextRuns[$Match.Groups[1].Value] = $Match.Groups[2].Value }
        $NextRuns.exchange | Should -Be '2026-12-01T00:00:00.0000000Z'
        $NextRuns.ContainsKey('teams') | Should -BeFalse
        ([datetimeoffset]::Parse($NextRuns.onedrive).UtcDateTime - [datetime]::UtcNow).Duration().TotalMinutes | Should -BeLessThan 1
        Should -Invoke New-CIPPCloudBackupKey -Times 0 -Exactly
        Should -Invoke Remove-CIPPCloudBackupRetentionRule -Times 1 -Exactly -ParameterFilter { $Destination.RowKey -eq $script:DestId -and $RuleName -eq "cipp-$($script:PolicyId)" }
    }

    It 'keeps the prune status on Edit' {
        $script:PolicyRows = @((New-CloudBackupPolicyRow) | Add-Member -NotePropertyMembers @{ LastPrunedAt = '2026-11-19T00:00:00.0000000Z'; PruneStatus = 'Failed'; PruneError = 'denied' } -PassThru)

        (Invoke-Policy -Body (New-PolicyBody -Overrides @{ Action = 'Edit'; Id = $script:PolicyId })).StatusCode | Should -Be 200

        $Saved = $script:Writes[0].Entity
        $Saved.LastPrunedAt | Should -Be '2026-11-19T00:00:00.0000000Z'
        $Saved.PruneStatus | Should -Be 'Failed'
        $Saved.PruneError | Should -Be 'denied'
    }

    It 'returns 404 when editing a policy that does not exist' {
        (Invoke-Policy -Body (New-PolicyBody -Overrides @{ Action = 'Edit'; Id = $script:PolicyId })).StatusCode | Should -Be 404
    }

    Context 'restricted caller' {
        BeforeEach { $script:Allowed = @('c1') }

        It 'returns 403 for a target outside their tenants: <Case>' -ForEach @(
            @{ Case = 'All Tenants'; Tenants = @([pscustomobject]@{ value = 'AllTenants'; type = 'Tenant' }) }
            @{ Case = 'a tenant group'; Tenants = @([pscustomobject]@{ value = 'g1'; type = 'Group' }) }
            @{ Case = 'another tenant'; Tenants = @([pscustomobject]@{ value = 'fabrikam.com'; type = 'Tenant' }) }
        ) {
            (Invoke-Policy -Body (New-PolicyBody -Overrides @{ Tenants = $Tenants })).StatusCode | Should -Be 403
            Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'saves a policy for their own tenant' {
            $Body = New-PolicyBody -Overrides @{ Tenants = @([pscustomobject]@{ value = 'contoso.com'; type = 'Tenant' }) }
            (Invoke-Policy -Body $Body).StatusCode | Should -Be 200
        }

        It 'returns 403 when editing, deleting or rotating a policy that reaches other tenants' -ForEach @(
            @{ Action = 'Edit' }, @{ Action = 'Delete' }, @{ Action = 'RotateKey' }
        ) {
            $script:PolicyRows = @(New-CloudBackupPolicyRow -Tenants '[{"type":"AllTenants"}]' -Encryption $true)
            $Body = New-PolicyBody -Overrides @{ Action = $Action; Id = $script:PolicyId; Tenants = @([pscustomobject]@{ value = 'contoso.com'; type = 'Tenant' }) }

            (Invoke-Policy -Body $Body).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    It 'records Pending permissions for every covered tenant and queues one grant task per tenant after saving' {
        $Response = Invoke-Policy -Body (New-PolicyBody)

        $Response.StatusCode | Should -Be 200
        "$($Response.Body.Results)" | Should -BeLike '*Granting permissions in 2 tenants*'
        $PolicyId = $script:Writes[0].Entity.RowKey
        @($script:PermissionWrites.RowKey | Sort-Object) | Should -Be @('c1', 'c2')
        @($script:PermissionWrites.Status | Select-Object -Unique) | Should -Be @('Pending')
        @($script:PermissionWrites.PartitionKey | Select-Object -Unique) | Should -Be @($PolicyId)
        $script:PermissionWrites[0].Workloads | Should -Be '["exchange","onedrive"]'
        $script:Started.Count | Should -Be 1
        $script:Started[0].OrchestratorName | Should -Be "CloudBackupGrant_$PolicyId"
        @($script:Started[0].Batch.FunctionName | Select-Object -Unique) | Should -Be @('CloudBackupGrant')
        @($script:Started[0].Batch.customerId | Sort-Object) | Should -Be @('c1', 'c2')
    }

    It 'GrantPermissions queues every tenant of the policy and accepts the request' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"},{"type":"Tenant","customerId":"c3"}]')

        $Response = Invoke-Policy -Body @{ Action = 'GrantPermissions'; Id = $script:PolicyId }

        $Response.StatusCode | Should -Be 202
        @($script:Started[0].Batch.customerId | Sort-Object) | Should -Be @('c1', 'c3')
        @($script:PermissionWrites.Status | Select-Object -Unique) | Should -Be @('Pending')
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'Config' }
    }

    It 'GrantPermissions for one tenant queues only that tenant, and refuses a tenant outside the policy' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"},{"type":"Tenant","customerId":"c3"}]')

        (Invoke-Policy -Body @{ Action = 'GrantPermissions'; Id = $script:PolicyId; TenantId = 'c3'; tenantFilter = 'contoso.com' }).StatusCode | Should -Be 202
        @($script:Started[0].Batch.customerId) | Should -Be @('c3')

        (Invoke-Policy -Body @{ Action = 'GrantPermissions'; Id = $script:PolicyId; TenantId = 'c2' }).StatusCode | Should -Be 400
        $script:Started.Count | Should -Be 1
    }

    It 'GrantPermissions returns 404 for an unknown policy and 403 to a restricted caller for a policy reaching other tenants' {
        (Invoke-Policy -Body @{ Action = 'GrantPermissions'; Id = $script:PolicyId }).StatusCode | Should -Be 404
        $script:PolicyRows = @(New-CloudBackupPolicyRow -Tenants '[{"type":"AllTenants"}]')
        $script:Allowed = @('c1')
        (Invoke-Policy -Body @{ Action = 'GrantPermissions'; Id = $script:PolicyId }).StatusCode | Should -Be 403
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'deletes the policy, its retention rule and its permission status' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow)
        $script:PermissionRows = @([pscustomobject]@{ PartitionKey = $script:PolicyId; RowKey = 'c1' })

        $Response = Invoke-Policy -Body @{ Action = 'Delete'; Id = $script:PolicyId }

        $Response.StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPCloudBackupRetentionRule -Times 1 -Exactly -ParameterFilter { $RuleName -eq "cipp-$($script:PolicyId)" }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq $script:PolicyId -and $Entity.PartitionKey -eq 'CloudBackupPolicy' }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupPermissions' -and $Entity.RowKey -eq 'c1' }
    }

    It 'still deletes the policy when the retention rule cannot be removed' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow)
        Mock Remove-CIPPCloudBackupRetentionRule { throw 'denied' }

        (Invoke-Policy -Body @{ Action = 'Delete'; Id = $script:PolicyId }).StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'Config' }
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'rotates the key: appends it to KeyIds and makes it current' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow -Encryption $true -CurrentKeyId 'k1' -KeyIds '["k1"]')

        $Response = Invoke-Policy -Body @{ Action = 'RotateKey'; Id = $script:PolicyId }

        $Response.StatusCode | Should -Be 200
        $Write = $script:Writes[0]
        $Write.OperationType | Should -Be 'UpsertMerge'
        $Write.Entity.CurrentKeyId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        @($Write.Entity.KeyIds | ConvertFrom-Json) | Should -Be @('k1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    }

    It 'refuses to rotate the key of a policy without encryption' {
        $script:PolicyRows = @(New-CloudBackupPolicyRow)

        (Invoke-Policy -Body @{ Action = 'RotateKey'; Id = $script:PolicyId }).StatusCode | Should -Be 400
        Should -Invoke New-CIPPCloudBackupKey -Times 0 -Exactly
    }
}
