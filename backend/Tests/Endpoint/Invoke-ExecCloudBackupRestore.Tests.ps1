BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    $Folder = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/CloudBackup'
    . (Join-Path $Folder 'Resolve-CIPPCloudBackupJobSource.ps1')
    function Get-CIPPCloudBackupRecoveryPoint { param($Destination, $OwnerPrefix) }

    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function Invoke-Restore {
        param([hashtable]$Body, $User = 'admin@partner.com')
        $Request = New-CloudBackupRequest -Endpoint 'ExecCloudBackupRestore' -Body $Body
        $Request.Headers['x-ms-client-principal-name'] = $User
        $Request.Headers['x-ms-client-principal-idp'] = 'aad'
        Invoke-ExecCloudBackupRestore -Request $Request
    }
    function New-Body {
        param([hashtable]$Extra = @{})
        $Body = @{ PolicyId = $script:PolicyId; TenantId = 'contoso.com'; Workload = 'exchange'; OwnerId = 'u1'; Keys = @('items/b.fts', 'items/a.fts'); Paths = @('/Inbox/'); Mode = 'Preview' }
        foreach ($Name in $Extra.PSBase.Keys) { $Body[$Name] = $Extra[$Name] }
        $Body
    }
}

Describe 'Invoke-ExecCloudBackupRestore' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1'; OwnerType = 'UserMailbox'; LastRunId = 'run-9'; Removed = $false; RemovedReason = '' }
        $script:Jobs = @{}
        $script:JobWrites = [System.Collections.Generic.List[object]]::new()
        $script:GraphRequests = [System.Collections.Generic.List[object]]::new()
        $script:Users = @{
            u1 = @{ id = 'u1'; userPrincipalName = 'one@contoso.com'; mail = 'one@contoso.com' }
            u2 = @{ id = 'u2'; userPrincipalName = 'two@contoso.com'; mail = 'two@contoso.com' }
            u3 = @{ id = 'u3'; userPrincipalName = 'three@contoso.com'; mail = $null }
        }
        $script:Drives = @{ u1 = 'drive-1'; u2 = 'drive-2' }
        $script:Sites = @{ 'site-1' = $true }
        $script:Queued = 'run-1'
        $script:Started = [System.Collections.Generic.List[object]]::new()

        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPCloudBackupPolicy { [pscustomobject]@{ Id = $script:PolicyId; Name = 'Nightly'; DestinationId = '22222222-2222-2222-2222-222222222222'; Encryption = $true; CurrentKeyId = '33333333-3333-3333-3333-333333333333' } }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupRecoveryPoint {
            @(
                [pscustomobject]@{ RunStamp = '20261103T000000Z'; At = [datetime]::new(2026, 11, 3, 0, 0, 0, [System.DateTimeKind]::Utc) }
                [pscustomobject]@{ RunStamp = '20261101T000000Z'; At = [datetime]::new(2026, 11, 1, 0, 0, 0, [System.DateTimeKind]::Utc) }
            )
        }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'run-9'; RowKey = 'u1'; DisplayName = 'User One'; UserPrincipalName = 'one@contoso.com' } } -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' }
        Mock Get-CIPPAzDataTableEntity { if ($Filter -match "RowKey eq '([^']+)'") { $script:Jobs[$Matches[1]] } } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { foreach ($Row in @($Entity)) { $script:JobWrites.Add([pscustomobject]@{ Entity = $Row; OperationType = $OperationType }) } } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                $script:GraphRequests.Add($Request)
                if ($Request.url -match '^sites/([^?]+)') {
                    $Id = [uri]::UnescapeDataString($Matches[1])
                    if ($script:Sites[$Id]) { @{ id = $Request.id; status = 200; body = @{ id = $Id } } } else { @{ id = $Request.id; status = 404; body = @{ error = @{ message = 'not found' } } } }
                } elseif ($Request.url -match '^users/([^/?]+)/drive') {
                    $Id = [uri]::UnescapeDataString($Matches[1])
                    if ($script:Drives[$Id]) { @{ id = $Request.id; status = 200; body = @{ id = $script:Drives[$Id] } } } else { @{ id = $Request.id; status = 404; body = @{ error = @{ message = 'not found' } } } }
                } elseif ($Request.url -match '^users/([^/?]+)') {
                    $Id = [uri]::UnescapeDataString($Matches[1])
                    if ($script:Users[$Id]) { @{ id = $Request.id; status = 200; body = $script:Users[$Id] } } else { @{ id = $Request.id; status = 404; body = @{ error = @{ message = 'not found' } } } }
                }
            }
        }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject); $script:Queued }
        Mock Write-LogMessage { }
    }

    It 'returns 400 for <Name>' -ForEach @(
        @{ Name = 'a bad policy id'; Extra = @{ PolicyId = 'x' }; Message = 'PolicyId*' }
        @{ Name = 'all tenants'; Extra = @{ TenantId = 'AllTenants' }; Message = 'TenantId*' }
        @{ Name = 'a Teams backup'; Extra = @{ Workload = 'teams' }; Message = 'Teams backups can be exported but not restored' }
        @{ Name = 'an unknown workload'; Extra = @{ Workload = 'intune' }; Message = 'Workload*' }
        @{ Name = 'a missing owner'; Extra = @{ OwnerId = '' }; Message = 'OwnerId*' }
        @{ Name = 'a bad mode'; Extra = @{ Mode = 'Now' }; Message = 'Mode*' }
        @{ Name = 'a bad location'; Extra = @{ Location = 'Elsewhere' }; Message = 'Location*' }
        @{ Name = 'a bad conflict action'; Extra = @{ ConflictAction = 'Merge' }; Message = 'ConflictAction*' }
        @{ Name = 'a bad AsOf'; Extra = @{ AsOf = 'yesterday-ish' }; Message = 'AsOf*' }
        @{ Name = 'Apply without a preview'; Extra = @{ Mode = 'Apply' }; Message = 'Run a restore preview first*' }
    ) {
        $Response = Invoke-Restore -Body (New-Body -Extra $Extra)
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike $Message
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'returns 404 for an unknown tenant, 403 for a tenant the caller cannot access and 404 for an owner without a backup' {
        (Invoke-Restore -Body (New-Body -Extra @{ TenantId = 'nope.com' })).StatusCode | Should -Be 404
        $script:Allowed = @('c2')
        (Invoke-Restore -Body (New-Body)).StatusCode | Should -Be 403
        $script:Allowed = @('AllTenants')
        $script:StateRow = $null
        (Invoke-Restore -Body (New-Body)).StatusCode | Should -Be 404
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'returns 404 when there is no backup at or before AsOf' {
        $Response = Invoke-Restore -Body (New-Body -Extra @{ AsOf = '2026-10-01T00:00:00Z' })
        $Response.StatusCode | Should -Be 404
        $Response.Body.Results | Should -BeLike '*at or before*'
    }

    It 'queues a preview to the original mailbox with only reads in the tenant' {
        $Response = Invoke-Restore -Body (New-Body -Extra @{ AsOf = '20261102T120000Z' })

        $Response.StatusCode | Should -Be 202
        $Response.Body.JobId | Should -Not -BeNullOrEmpty
        $Job = $script:JobWrites[0].Entity
        $Job.Type | Should -Be 'RestorePreview'
        $Job.RunStamp | Should -Be '20261101T000000Z'
        $Job.SourceTenantId | Should -Be 'c1'
        $Job.SourceOwnerName | Should -Be 'User One'
        $Job.TargetOwnerId | Should -Be 'u1'
        $Job.TargetUserPrincipalName | Should -Be 'one@contoso.com'
        $Job.Location | Should -Be 'RestoredFolder'
        $Job.ConflictAction | Should -Be 'Skip'
        $Job.RestoredFolderName | Should -Match '^Restored \d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
        $Job.DataKeyId | Should -Be '33333333-3333-3333-3333-333333333333'
        $Job.ManifestJobId | Should -Be $Response.Body.JobId
        $Job.ManifestReady | Should -BeFalse
        $Parameters = [CIPP.CippJson]::ConvertFromJson($Job.Parameters)
        @($Parameters.Keys) | Should -Be @('items/a.fts', 'items/b.fts')
        @($Parameters.Paths) | Should -Be @('Inbox')
        $Parameters.RestoredFolderName | Should -Be $Job.RestoredFolderName
        @($script:GraphRequests).Where({ $_.method -ne 'GET' }).Count | Should -Be 0
        $script:Started[0].Batch[0].FunctionName | Should -Be 'CloudBackupRestore'
        $script:Started[0].Batch[0].JobId | Should -Be $Response.Body.JobId
        Should -Invoke Write-LogMessage -ParameterFilter { $API -eq 'CloudBackupRestore' -and $sev -eq 'Info' -and $message -like 'Previewing*' }
    }

    It 'refuses the original owner when it was removed from the tenant, and restores to another user' {
        $script:StateRow.Removed = $true
        $script:StateRow.RemovedReason = 'Removed'
        $Response = Invoke-Restore -Body (New-Body)
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*Choose another user*'

        $Response = Invoke-Restore -Body (New-Body -Extra @{ TargetOwnerId = @{ value = 'u2'; label = 'Two' } })
        $Response.StatusCode | Should -Be 202
        $script:JobWrites[0].Entity.TargetOwnerId | Should -Be 'u2'
        $script:JobWrites[0].Entity.SourceRemoved | Should -BeTrue
    }

    It 'allows the original owner of an excluded owner' {
        $script:StateRow.Removed = $true
        $script:StateRow.RemovedReason = 'Excluded'
        (Invoke-Restore -Body (New-Body)).StatusCode | Should -Be 202
    }

    It 'returns 400 when the original user is gone and 404 when another target user is not found' {
        $script:Users.Remove('u1')
        $Response = Invoke-Restore -Body (New-Body)
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*no longer exists*'
        (Invoke-Restore -Body (New-Body -Extra @{ TargetOwnerId = 'u9' })).StatusCode | Should -Be 404
    }

    It 'returns 400 for a mailbox target without a mailbox and a OneDrive target without a OneDrive' {
        (Invoke-Restore -Body (New-Body -Extra @{ TargetOwnerId = 'u3' })).Body.Results | Should -BeLike '*has no mailbox*'
        $Response = Invoke-Restore -Body (New-Body -Extra @{ Workload = 'onedrive'; TargetOwnerId = 'u3' })
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*has no OneDrive*'
    }

    It 'restores OneDrive files to another user''s OneDrive' {
        $script:StateRow.RowKey = 'onedrive_u1'
        (Invoke-Restore -Body (New-Body -Extra @{ Workload = 'onedrive'; TargetOwnerId = 'u2'; Location = 'Original'; ConflictAction = 'Copy' })).StatusCode | Should -Be 202
        $Job = $script:JobWrites[0].Entity
        $Job.TargetDriveId | Should -Be 'drive-2'
        $Job.TargetOwnerType | Should -Be 'User'
        $Job.Location | Should -Be 'Original'
        $Job.ConflictAction | Should -Be 'Copy'
    }

    It 'restores a SharePoint site to itself, and refuses when the site is gone' {
        $Response = Invoke-Restore -Body (New-Body -Extra @{ Workload = 'sharepoint'; OwnerId = 'site-1' })
        $Response.StatusCode | Should -Be 202
        $Job = $script:JobWrites[0].Entity
        $Job.TargetOwnerType | Should -Be 'Site'
        $Job.TargetSiteId | Should -Be 'site-1'

        $script:Sites.Remove('site-1')
        $Response = Invoke-Restore -Body (New-Body -Extra @{ Workload = 'sharepoint'; OwnerId = 'site-1' })
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike "*Restore to a user's OneDrive instead*"
    }

    Context 'Apply' {
        BeforeEach {
            $Response = Invoke-Restore -Body (New-Body)
            $script:PreviewId = $Response.Body.JobId
            $Preview = [pscustomobject]$script:JobWrites[0].Entity
            $Preview.Status = 'Completed'
            $Preview.ItemCount = 42
            $Preview.ManifestReady = $true
            $Preview.PSObject.Properties.Add([psnoteproperty]::new('AppliedJobId', ''))
            $script:Jobs[$script:PreviewId] = $Preview
            $script:JobWrites.Clear()
            $script:Started.Clear()
        }

        It 'refuses <Name>' -ForEach @(
            @{ Name = 'a preview that does not exist'; Change = { $script:Jobs.Clear() }; Message = 'The preview was not found*' }
            @{ Name = 'a preview that has not completed'; Change = { $script:Jobs[$script:PreviewId].Status = 'Running' }; Message = '*has not completed*' }
            @{ Name = 'a preview that was already used'; Change = { $script:Jobs[$script:PreviewId].AppliedJobId = 'other' }; Message = '*already used*' }
            @{ Name = 'a preview of another user'; Change = { $script:Jobs[$script:PreviewId].RequestedBy = 'someone@partner.com' }; Message = '*another user*' }
            @{ Name = 'a preview older than 60 minutes'; Change = { $script:Jobs[$script:PreviewId].CreatedAt = [datetime]::UtcNow.AddMinutes(-61).ToString('o') }; Message = '*more than 60 minutes*' }
            @{ Name = 'different options'; Change = { $script:ApplyExtra = @{ ConflictAction = 'Overwrite' } }; Message = '*differ from the preview*' }
            @{ Name = 'a different target'; Change = { $script:ApplyExtra = @{ TargetOwnerId = 'u2' } }; Message = '*differ from the preview*' }
        ) {
            $script:ApplyExtra = @{}
            & $Change
            $Extra = @{ Mode = 'Apply'; PreviewJobId = $script:PreviewId }
            foreach ($Name in $script:ApplyExtra.PSBase.Keys) { $Extra[$Name] = $script:ApplyExtra[$Name] }

            $Response = Invoke-Restore -Body (New-Body -Extra $Extra)

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -BeLike $Message
            $script:Started.Count | Should -Be 0
            $script:JobWrites.Count | Should -Be 0
        }

        It 'queues the restore with the preview''s manifest, point in time and folder name, and marks the preview used' {
            $Response = Invoke-Restore -Body (New-Body -Extra @{ Mode = 'Apply'; PreviewJobId = $script:PreviewId; Keys = @('items/a.fts', 'items/b.fts', 'items/a.fts') })

            $Response.StatusCode | Should -Be 202
            $Job = $script:JobWrites[0].Entity
            $Job.Type | Should -Be 'Restore'
            $Job.PreviewJobId | Should -Be $script:PreviewId
            $Job.ManifestJobId | Should -Be $script:PreviewId
            $Job.ManifestReady | Should -BeTrue
            $Job.ItemCount | Should -Be 42
            $Job.RunStamp | Should -Be '20261103T000000Z'
            $Job.RestoredFolderName | Should -Be $script:Jobs[$script:PreviewId].RestoredFolderName
            $script:JobWrites[1].Entity.RowKey | Should -Be $script:PreviewId
            $script:JobWrites[1].Entity.AppliedJobId | Should -Be $Response.Body.JobId
            $script:JobWrites[1].OperationType | Should -Be 'UpsertMerge'
            Should -Invoke Get-CIPPCloudBackupRecoveryPoint -Times 1 -Exactly
            Should -Invoke Write-LogMessage -ParameterFilter { $API -eq 'CloudBackupRestore' -and $message -like 'Restoring*' }
        }

        It 'returns 500 and frees the preview when the restore cannot be queued' {
            $script:Queued = $null
            $Response = Invoke-Restore -Body (New-Body -Extra @{ Mode = 'Apply'; PreviewJobId = $script:PreviewId })
            $Response.StatusCode | Should -Be 500
            $Response.Body.JobId | Should -BeNullOrEmpty
            @($script:JobWrites).Where({ $_.Entity.Status -eq 'Failed' }).Count | Should -Be 1
            @($script:JobWrites).Where({ $_.Entity.RowKey -eq $script:PreviewId -and $_.Entity.AppliedJobId -eq '' }).Count | Should -Be 1
        }
    }
}
