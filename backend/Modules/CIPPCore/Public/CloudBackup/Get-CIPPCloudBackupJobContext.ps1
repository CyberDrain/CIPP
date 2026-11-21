function Get-CIPPCloudBackupJobContext {
    <#
    .SYNOPSIS
        Builds the restore or export context for a cloud backup job row.
    .DESCRIPTION
        Returns { JobId; PolicyId; TenantId; TenantFilter; Workload; SourceOwnerId; SourceOwnerType; SourceRemoved;
        Target; Location; RestoredFolderName; ConflictAction; AsOf; RunStamp; Destination; KeyId; Key; OwnerPrefix;
        Apply; ManifestJobId }. KeyId and Key are the job's data key (the policy key when the job was created), used for
        the job's manifests, results and export; stored items name their own key.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Job
    )

    $Policy = Get-CIPPCloudBackupPolicy -Id $Job.PolicyId
    if (-not $Policy) { throw [System.Management.Automation.ItemNotFoundException]::new("Cloud backup policy $($Job.PolicyId) no longer exists") }
    $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
    if (-not $Destination) { throw [System.Management.Automation.ItemNotFoundException]::new("Destination $($Policy.DestinationId) no longer exists") }
    $Tenant = (Get-CIPPTenantLookup)["$($Job.SourceTenantId)"]
    if (-not $Tenant) { throw [System.Management.Automation.ItemNotFoundException]::new("Tenant $($Job.SourceTenantId) was not found") }

    $KeyId = if ($Job.DataKeyId) { "$($Job.DataKeyId)" } else { $null }
    $Key = if ($KeyId) { Get-CIPPCloudBackupKey -KeyId $KeyId } else { $null }
    $SafeOwnerId = "$($Job.SourceOwnerId)" -replace "[/\\#?'\u0000-\u001F\u007F-\u009F]", '_'

    [pscustomobject]@{
        JobId              = "$($Job.RowKey)"
        PolicyId           = "$($Job.PolicyId)"
        TenantId           = "$($Tenant.customerId)"
        TenantFilter       = "$($Tenant.defaultDomainName)"
        Workload           = "$($Job.Workload)"
        SourceOwnerId      = "$($Job.SourceOwnerId)"
        SourceOwnerType    = "$($Job.SourceOwnerType)"
        SourceOwnerName    = "$($Job.SourceOwnerName)"
        SourceRemoved      = "$($Job.SourceRemoved)" -eq 'True'
        Target             = @{
            OwnerId           = if ($Job.TargetOwnerId) { "$($Job.TargetOwnerId)" } else { $null }
            OwnerType         = if ($Job.TargetOwnerType) { "$($Job.TargetOwnerType)" } else { $null }
            UserPrincipalName = if ($Job.TargetUserPrincipalName) { "$($Job.TargetUserPrincipalName)" } else { $null }
            SiteId            = if ($Job.TargetSiteId) { "$($Job.TargetSiteId)" } else { $null }
            DriveId           = if ($Job.TargetDriveId) { "$($Job.TargetDriveId)" } else { $null }
        }
        Location           = if ($Job.Location) { "$($Job.Location)" } else { 'RestoredFolder' }
        RestoredFolderName = "$($Job.RestoredFolderName)"
        ConflictAction     = if ($Job.ConflictAction) { "$($Job.ConflictAction)" } else { 'Skip' }
        AsOf               = "$($Job.AsOf)"
        RunStamp           = "$($Job.RunStamp)"
        Destination        = $Destination
        KeyId              = $KeyId
        Key                = $Key
        OwnerPrefix        = "$($Job.PolicyId)/$($Tenant.customerId)/$($Job.Workload)/$SafeOwnerId/"
        Apply              = "$($Job.Type)" -eq 'Restore'
        ManifestJobId      = if ($Job.ManifestJobId) { "$($Job.ManifestJobId)" } else { "$($Job.RowKey)" }
    }
}
