function Push-CloudBackupRestore {
    <#
    .SYNOPSIS
        Runs a cloud backup restore preview or restore job step by step
    .DESCRIPTION
        Writes the job's item manifest (a restore reuses its preview's), then runs the workload's restore step until it
        reports Done. After every step the results page and the step state are saved on the job, so a stopped job that is
        queued again resumes from the last saved step.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $JobId = "$($Item.JobId)"
    $PageSize = 1000
    $Names = @{ exchange = 'Exchange'; onedrive = 'OneDrive'; sharepoint = 'SharePoint' }
    $Table = $null
    $Row = $null
    $TenantFilter = $null
    $ErrorText = ''
    $FailedLogged = 0

    try {
        if (-not ($JobId -as [guid])) { throw "Cloud backup job id '$JobId' is not valid" }
        $Table = Get-CIPPTable -TableName 'CloudBackupJobs'
        $Job = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CloudBackupJob' and RowKey eq '$([guid]$JobId)'")[0]
        if (-not $Job) { throw "Cloud backup job $JobId was not found" }
        if ($Job.Status -in @('Completed', 'Failed')) { return }

        $Row = @{
            PartitionKey = 'CloudBackupJob'
            RowKey       = $Job.RowKey
            Status       = 'Running'
            StartedAt    = if ($Job.StartedAt) { "$($Job.StartedAt)" } else { [datetime]::UtcNow.ToString('o') }
            UpdatedAt    = [datetime]::UtcNow.ToString('o')
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Row -OperationType 'UpsertMerge'

        $Context = Get-CIPPCloudBackupJobContext -Job $Job
        $TenantFilter = $Context.TenantFilter
        $Mode = if ($Context.Apply) { 'Restore' } else { 'Restore preview' }
        $TargetName = if ($Context.Target.OwnerType -eq 'Site') { "$($Job.SourceOwnerName)" } else { $Context.Target.UserPrincipalName }
        if (-not $Names.ContainsKey($Context.Workload)) { throw [System.ArgumentException]::new("$($Context.Workload) backups cannot be restored") }
        $StepCommand = "Invoke-CIPPCloudBackup$($Names[$Context.Workload])RestoreStep"

        $Resumed = [bool]$Job.State -or ($Job.ResultCount -as [int]) -gt 0
        $Verb = if ($Resumed) { 'resumed' } else { 'started' }
        Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -tenantid $Context.TenantId -message "$Mode $JobId $Verb for $($Job.RequestedBy): $($Context.Workload) backup of $($Job.SourceOwnerName) ($($Context.RunStamp)) to $TargetName, conflicts: $($Context.ConflictAction), location: $($Context.Location)" -sev Info

        $ItemCount = [int]($Job.ItemCount -as [int])
        if ("$($Job.ManifestReady)" -ne 'True') {
            $Parameters = if ($Job.Parameters) { [CIPP.CippJson]::ConvertFromJson([string]$Job.Parameters) } else { $null }
            $Manifest = Save-CIPPCloudBackupJobManifest -Context $Context -Keys @($Parameters.Keys) -Paths @($Parameters.Paths)
            $ItemCount = [int]$Manifest.Items
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; ManifestReady = $true; ItemCount = $ItemCount; UpdatedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'
        }

        $Summary = [ordered]@{ Items = $ItemCount; Processed = 0; Create = 0; Overwrite = 0; Copy = 0; Skip = 0; NotRestorable = 0; Planned = 0; Succeeded = 0; Failed = 0; Skipped = 0; Bytes = [int64]0 }
        if ($Job.Summary) {
            $Saved = [CIPP.CippJson]::ConvertFromJson([string]$Job.Summary)
            foreach ($Name in @($Summary.Keys)) { if ($null -ne $Saved.$Name) { $Summary[$Name] = $Saved.$Name } }
            $Summary.Items = $ItemCount
        }
        $State = if ($Job.State) { ConvertFrom-Json -InputObject ([string]$Job.State) -AsHashtable } else { $null }
        $ResultCount = [int]($Job.ResultCount -as [int])
        $Suffix = if ($Context.KeyId) { '.enc' } else { '' }
        $PageWrite = @{ Destination = $Context.Destination }
        if ($Context.KeyId) {
            $PageWrite.KeyId = $Context.KeyId
            $PageWrite.EncryptionKey = $Context.Key
        }
        $PageIndex = [int][Math]::Floor($ResultCount / $PageSize)
        $Page = [System.Collections.Generic.List[object]]::new()
        if ($ResultCount % $PageSize -ne 0) {
            $Existing = Get-CIPPCloudBackupJsonl -Destination $Context.Destination -Key ('{0}/jobs/{1}/results/{2:D5}.jsonl.gz{3}' -f $Context.PolicyId, $Context.JobId, $PageIndex, $Suffix)
            foreach ($Saved in @($Existing)) { if ($null -ne $Saved) { $Page.Add($Saved) } }
        }

        while ($true) {
            $Step = & $StepCommand -Context $Context -State $State
            if ($null -eq $Step) { throw "The $($Context.Workload) restore step returned no result" }
            $Results = @(foreach ($Result in @($Step.Results)) { if ($null -ne $Result) { $Result } })
            foreach ($Result in $Results) {
                $Summary.Processed++
                $Action = "$($Result.Action)"
                $Status = "$($Result.Status)"
                if ($Summary.Contains($Action)) { $Summary[$Action]++ }
                if ($Summary.Contains($Status)) { $Summary[$Status]++ }
                if ($Status -eq 'Failed' -and $FailedLogged -lt 200) {
                    $FailedLogged++
                    Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -tenantid $Context.TenantId -message "$Mode $JobId could not restore '$($Result.Path)/$($Result.Name)' to $($TargetName): $($Result.Message)" -sev Warning
                }
                $Page.Add([pscustomobject]@{
                        Key        = $Result.Key
                        Name       = $Result.Name
                        Path       = $Result.Path
                        Type       = $Result.Type
                        Action     = $Action
                        Status     = $Status
                        Message    = $Result.Message
                        TargetPath = $Result.TargetPath
                    })
                if ($Page.Count -ge $PageSize) {
                    $null = Set-CIPPCloudBackupJsonl @PageWrite -Key ('{0}/jobs/{1}/results/{2:D5}.jsonl.gz{3}' -f $Context.PolicyId, $Context.JobId, $PageIndex, $Suffix) -Items $Page.ToArray() -Confirm:$false
                    $PageIndex++
                    $Page.Clear()
                }
            }
            if ($Results.Count -gt 0 -and $Page.Count -gt 0) {
                $null = Set-CIPPCloudBackupJsonl @PageWrite -Key ('{0}/jobs/{1}/results/{2:D5}.jsonl.gz{3}' -f $Context.PolicyId, $Context.JobId, $PageIndex, $Suffix) -Items $Page.ToArray() -Confirm:$false
            }
            $ResultCount += $Results.Count
            $Summary.Bytes += [int64]$Step.Bytes
            $State = $Step.State
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'CloudBackupJob'
                RowKey       = $Job.RowKey
                State        = if ($null -eq $State) { '' } else { [CIPP.CippJson]::ToJson($State, 20) ?? (ConvertTo-Json -InputObject $State -Depth 20 -Compress) }
                ResultCount  = $ResultCount
                ResultPages  = [int][Math]::Ceiling($ResultCount / $PageSize)
                Summary      = [CIPP.CippJson]::ToJson($Summary, 3) ?? (ConvertTo-Json -InputObject $Summary -Compress)
                UpdatedAt    = [datetime]::UtcNow.ToString('o')
            } -OperationType 'UpsertMerge'
            if ($Step.Done) { break }
        }

        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; Status = 'Completed'; CompletedAt = [datetime]::UtcNow.ToString('o'); UpdatedAt = [datetime]::UtcNow.ToString('o'); Error = '' } -OperationType 'UpsertMerge'
        $Counts = foreach ($Name in $Summary.Keys) { if ($Name -ne 'Bytes' -and $Summary[$Name]) { "$Name $($Summary[$Name])" } }
        $Severity = if ($Summary.Failed -gt 0) { 'Warning' } else { 'Info' }
        Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -tenantid $Context.TenantId -message "$Mode $JobId requested by $($Job.RequestedBy) of $($Job.SourceOwnerName) to $TargetName completed: $($Counts -join ', ')" -sev $Severity
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = "$($ErrorMessage.NormalizedError)"
        if ($Row) {
            try {
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Row.RowKey; Status = 'Failed'; Error = $ErrorText; CompletedAt = [datetime]::UtcNow.ToString('o'); UpdatedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'
            } catch {
                Write-Information "Could not record cloud backup job $($JobId): $($_.Exception.Message)"
            }
        }
        try { Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -message "Cloud backup restore job $JobId failed: $ErrorText" -sev Error -LogData $ErrorMessage } catch { Write-Information $ErrorText }
    }
}
