function Push-CloudBackupOwner {
    <#
    .SYNOPSIS
        Backs up one owner (mailbox, OneDrive, site, team or chat user) of a cloud backup run, step by step
    .DESCRIPTION
        Runs the workload's steps until it reports Done. After every step the step's index entries are written as an
        index part and the workload's state is saved, so a run that is stopped resumes from the last saved step.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $PolicyId = "$($Item.PolicyId)"
    $TenantId = "$($Item.customerId)"
    $Workload = "$($Item.Workload)".ToLowerInvariant()
    $OwnerId = "$($Item.OwnerId)"
    $RunId = "$($Item.RunId)"
    $SafeOwnerId = $OwnerId -replace "[/\\#?'\u0000-\u001F\u007F-\u009F]", '_'
    $Names = @{ exchange = 'Exchange'; onedrive = 'OneDrive'; sharepoint = 'SharePoint'; teams = 'Teams' }
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $WarningCount = 0
    $ErrorText = ''
    $Tenant = $null
    $Result = @{
        PartitionKey      = $RunId
        RowKey            = $SafeOwnerId
        OwnerId           = $OwnerId
        OwnerType         = "$($Item.OwnerType)"
        DisplayName       = "$($Item.DisplayName)"
        UserPrincipalName = "$($Item.UserPrincipalName)"
        SiteUrl           = "$($Item.SiteUrl)"
        Status            = 'Running'
        Items             = 0
        Bytes             = [int64]0
        Deleted           = 0
        Steps             = 0
        WarningCount      = 0
        Warnings          = '[]'
        Error             = ''
        StartedAt         = [datetime]::UtcNow.ToString('o')
        CompletedAt       = ''
    }
    $ResultsTable = $null
    $StateTable = $null
    $StateRow = $null

    try {
        $ResultsTable = Get-CIPPTable -TableName 'CloudBackupRunOwners'
        Add-CIPPAzDataTableEntity @ResultsTable -Entity $Result -Force

        if (-not $Names.ContainsKey($Workload)) { throw "Unknown cloud backup workload '$Workload'" }
        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) { throw "Cloud backup policy $PolicyId no longer exists" }
        $Tenant = @(Get-Tenants -TenantFilter $TenantId)[0]
        if (-not $Tenant) { throw "Tenant $TenantId was not found or is excluded" }
        $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
        if (-not $Destination) { throw "Destination $($Policy.DestinationId) no longer exists" }
        $KeyId = $null
        $Key = $null
        if ($Policy.Encryption) {
            if (-not $Policy.CurrentKeyId) { throw 'Encryption is on but the policy has no encryption key' }
            $KeyId = $Policy.CurrentKeyId
            $Key = Get-CIPPCloudBackupKey -KeyId $KeyId
        }

        $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
        $StatePartition = "$($PolicyId)_$TenantId"
        $StateRowKey = "$($Workload)_$SafeOwnerId"
        $Stored = @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$StatePartition' and RowKey eq '$StateRowKey'")[0]
        $StateRow = @{
            PartitionKey      = $StatePartition
            RowKey            = $StateRowKey
            OwnerId           = $OwnerId
            OwnerType         = "$($Item.OwnerType ?? $Stored.OwnerType)"
            State             = "$($Stored.State)"
            Status            = 'Running'
            LastRunId         = $RunId
            LastSuccessAt     = "$($Stored.LastSuccessAt)"
            LastError         = ''
            Items             = [int64]($Stored.Items -as [int64])
            Bytes             = [int64]($Stored.Bytes -as [int64])
            IndexRunId        = $RunId
            IndexPart         = if ("$($Stored.IndexRunId)" -eq $RunId) { [int]($Stored.IndexPart -as [int]) } else { 0 }
            UpdatedAt         = [datetime]::UtcNow.ToString('o')
            DisplayName       = "$($Item.DisplayName)"
            UserPrincipalName = "$($Item.UserPrincipalName)"
            SiteUrl           = "$($Item.SiteUrl)"
            LastCompactedAt   = "$($Stored.LastCompactedAt)"
            Removed           = $false
            RemovedAt         = ''
            RemovedReason     = ''
        }
        $State = if ($StateRow.State) { ConvertFrom-Json -InputObject $StateRow.State -AsHashtable } else { $null }

        $Context = [pscustomobject]@{
            TenantFilter = $Tenant.defaultDomainName
            TenantId     = $TenantId
            PolicyId     = $PolicyId
            Workload     = $Workload
            OwnerId      = $OwnerId
            OwnerType    = $StateRow.OwnerType
            Owner        = [pscustomobject]@{
                OwnerId           = $OwnerId
                OwnerType         = $StateRow.OwnerType
                DisplayName       = $Item.DisplayName
                UserId            = $Item.UserId
                UserPrincipalName = $Item.UserPrincipalName
                SiteUrl           = $Item.SiteUrl
            }
            RunId        = $RunId
            RunStamp     = "$($Item.RunStamp)"
            Destination  = $Destination
            KeyId        = $KeyId
            Key          = $Key
            OwnerPrefix  = "$PolicyId/$TenantId/$Workload/$SafeOwnerId/"
        }
        $StepCommand = "Invoke-CIPPCloudBackup$($Names[$Workload])Step"

        while ($true) {
            $Step = & $StepCommand -Context $Context -State $State
            $Entries = @(foreach ($Entry in @($Step.IndexEntries)) { if ($null -ne $Entry) { $Entry } })
            if ($Entries.Count -gt 0) {
                $Buffer = [System.IO.MemoryStream]::new()
                try {
                    $Gzip = [System.IO.Compression.GZipStream]::new($Buffer, [System.IO.Compression.CompressionLevel]::Optimal, $true)
                    $Writer = [System.IO.StreamWriter]::new($Gzip, [System.Text.UTF8Encoding]::new($false))
                    foreach ($Entry in $Entries) {
                        $Writer.Write(([CIPP.CippJson]::ToJson($Entry, 10) ?? (ConvertTo-Json -InputObject $Entry -Depth 10 -Compress)))
                        $Writer.Write("`n")
                    }
                    $Writer.Dispose()
                    $Buffer.Position = 0
                    $IndexKey = 'index/{0}-{1:D5}.jsonl.gz' -f $Context.RunStamp, $StateRow.IndexPart
                    if ($Key) { $IndexKey = "$IndexKey.enc" }
                    $null = Write-CIPPCloudBackupItem -Context $Context -ItemKey $IndexKey -Stream $Buffer -ContentType 'application/gzip'
                } finally {
                    $Buffer.Dispose()
                }
                $StateRow.IndexPart++
            }

            $State = $Step.State
            $Result.Steps++
            $Result.Items += [int]$Step.Items
            $Result.Bytes += [int64]$Step.Bytes
            $Result.Deleted += [int]$Step.Deleted
            foreach ($Warning in @($Step.Warnings)) {
                if (-not $Warning) { continue }
                $WarningCount++
                if ($Warnings.Count -lt 50) { $Warnings.Add("$Warning") }
            }

            $StateRow.State = if ($null -eq $State) { '' } else { [CIPP.CippJson]::ToJson($State, 20) ?? (ConvertTo-Json -InputObject $State -Depth 20 -Compress) }
            $StateRow.Items += [int64]$Step.Items
            $StateRow.Bytes += [int64]$Step.Bytes
            $StateRow.UpdatedAt = [datetime]::UtcNow.ToString('o')
            if ($Step.Done) {
                $StateRow.Status = 'Idle'
                $StateRow.LastSuccessAt = $StateRow.UpdatedAt
            }
            Add-CIPPAzDataTableEntity @StateTable -Entity $StateRow -Force
            if ($Step.Done) { break }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = "$($ErrorMessage.NormalizedError)"
        if ($StateRow) {
            $StateRow.Status = 'Error'
            $StateRow.LastError = $ErrorText
            $StateRow.UpdatedAt = [datetime]::UtcNow.ToString('o')
            try { Add-CIPPAzDataTableEntity @StateTable -Entity $StateRow -Force } catch { Write-Information "Could not save cloud backup state for $($OwnerId): $($_.Exception.Message)" }
        }
    } finally {
        $Result.Status = if ($ErrorText) { 'Failed' } elseif ($WarningCount -gt 0) { 'PartialSuccess' } else { 'Succeeded' }
        $Result.Error = $ErrorText
        $Result.WarningCount = $WarningCount
        $Result.Warnings = [CIPP.CippJson]::ToJson($Warnings, 2) ?? (ConvertTo-Json -InputObject @($Warnings) -Compress)
        $Result.CompletedAt = [datetime]::UtcNow.ToString('o')
        try {
            $ResultsTable = $ResultsTable ?? (Get-CIPPTable -TableName 'CloudBackupRunOwners')
            Add-CIPPAzDataTableEntity @ResultsTable -Entity $Result -Force
        } catch {
            Write-Information "Could not record the cloud backup result for $($OwnerId): $($_.Exception.Message)"
        }
        if ($ErrorText) {
            Write-LogMessage -API 'CloudBackup' -tenant $Tenant.defaultDomainName -tenantid $TenantId -message "Cloud backup of $($Item.DisplayName ?? $OwnerId) ($Workload) failed: $ErrorText" -sev Error
        }
    }
}
