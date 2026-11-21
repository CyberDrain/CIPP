function Get-CIPPCloudBackupOwnerSource {
    <#
    .SYNOPSIS
        Resolves a backed-up owner to its policy, destination, state row and storage prefix as { Policy; Destination; State; OwnerPrefix }.
    .DESCRIPTION
        Throws ItemNotFoundException when the policy, its destination or the owner's backup does not exist.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('exchange', 'onedrive', 'sharepoint', 'teams')]
        [string]$Workload,

        [Parameter(Mandatory = $true)]
        [string]$OwnerId
    )

    $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
    if (-not $Policy) { throw [System.Management.Automation.ItemNotFoundException]::new("Cloud backup policy $PolicyId was not found") }
    $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
    if (-not $Destination) { throw [System.Management.Automation.ItemNotFoundException]::new("The destination of cloud backup policy $($Policy.Name) no longer exists") }

    $Workload = $Workload.ToLowerInvariant()
    $SafeOwnerId = $OwnerId -replace "[/\\#?'\u0000-\u001F\u007F-\u009F]", '_'
    $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
    $State = @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$($Policy.Id)_$TenantId' and RowKey eq '$($Workload)_$SafeOwnerId'" -Property PartitionKey, RowKey, OwnerId, OwnerType, DisplayName, UserPrincipalName, SiteUrl, Removed, RemovedAt, RemovedReason, LastSuccessAt)[0]
    if (-not $State) { throw [System.Management.Automation.ItemNotFoundException]::new("There is no $Workload backup of $OwnerId in policy $($Policy.Name)") }

    [pscustomobject]@{
        Policy      = $Policy
        Destination = $Destination
        State       = $State
        OwnerPrefix = "$($Policy.Id)/$TenantId/$Workload/$SafeOwnerId/"
    }
}
