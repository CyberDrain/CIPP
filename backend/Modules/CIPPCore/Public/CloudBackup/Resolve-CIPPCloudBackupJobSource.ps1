function Resolve-CIPPCloudBackupJobSource {
    <#
    .SYNOPSIS
        Resolves the backed-up owner a restore, export or download reads from, and its point in time.
    .DESCRIPTION
        Returns { Policy; Destination; OwnerId; SafeOwnerId; OwnerType; DisplayName; UserPrincipalName; SiteUrl;
        Removed; RemovedReason; OwnerPrefix; RunStamp; At }. -AsOf is a RunStamp (yyyyMMddTHHmmssZ) or a date and time;
        the newest recovery point at or before it is used, the newest overall when it is empty. With -SkipRecoveryPoint
        RunStamp and At are $null. Throws ItemNotFoundException for a missing policy, destination, owner or recovery
        point and ArgumentException for an AsOf that is not a date.
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
        [string]$Workload,

        [Parameter(Mandatory = $true)]
        [string]$OwnerId,

        [string]$AsOf,

        [switch]$SkipRecoveryPoint
    )

    $AsOfTime = $null
    if ($AsOf -and -not $SkipRecoveryPoint) {
        $Parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParseExact($AsOf, 'yyyyMMddTHHmmssZ', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed) -or
            [datetimeoffset]::TryParse($AsOf, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
            $AsOfTime = $Parsed.UtcDateTime
        } else {
            throw [System.ArgumentException]::new("AsOf '$AsOf' is not a recovery point or a date and time")
        }
    }

    $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
    if (-not $Policy) { throw [System.Management.Automation.ItemNotFoundException]::new("Policy $PolicyId was not found") }
    $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
    if (-not $Destination) { throw [System.Management.Automation.ItemNotFoundException]::new("The destination of policy $($Policy.Name) no longer exists") }

    $SafeOwnerId = $OwnerId -replace "[/\\#?'\u0000-\u001F\u007F-\u009F]", '_'
    $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
    $State = @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$($PolicyId)_$TenantId' and RowKey eq '$($Workload)_$SafeOwnerId'")[0]
    if (-not $State) { throw [System.Management.Automation.ItemNotFoundException]::new("Policy $($Policy.Name) has no $Workload backup of $OwnerId") }

    $Info = $null
    if ($State.LastRunId) {
        $OwnersTable = Get-CIPPTable -TableName 'CloudBackupRunOwners'
        $Info = @(Get-CIPPAzDataTableEntity @OwnersTable -Filter "PartitionKey eq '$($State.LastRunId)' and RowKey eq '$SafeOwnerId'" -Property PartitionKey, RowKey, DisplayName, UserPrincipalName, SiteUrl)[0]
    }
    $OwnerPrefix = "$PolicyId/$TenantId/$Workload/$SafeOwnerId/"

    $RunStamp = $null
    $At = $null
    if (-not $SkipRecoveryPoint) {
        foreach ($Point in @(Get-CIPPCloudBackupRecoveryPoint -Destination $Destination -OwnerPrefix $OwnerPrefix)) {
            if ($null -eq $Point) { continue }
            if ($null -eq $AsOfTime -or ([datetime]$Point.At).ToUniversalTime() -le $AsOfTime) {
                $RunStamp = "$($Point.RunStamp)"
                $At = $Point.At
                break
            }
        }
        if (-not $RunStamp) {
            $When = if ($AsOf) { " at or before $AsOf" } else { '' }
            throw [System.Management.Automation.ItemNotFoundException]::new("There is no backup of $OwnerId$When")
        }
    }

    [pscustomobject]@{
        Policy            = $Policy
        Destination       = $Destination
        OwnerId           = $OwnerId
        SafeOwnerId       = $SafeOwnerId
        OwnerType         = "$($State.OwnerType)"
        DisplayName       = if ($Info.DisplayName) { "$($Info.DisplayName)" } else { $OwnerId }
        UserPrincipalName = if ($Info.UserPrincipalName) { "$($Info.UserPrincipalName)" } else { $null }
        SiteUrl           = if ($Info.SiteUrl) { "$($Info.SiteUrl)" } else { $null }
        Removed           = "$($State.Removed)" -eq 'True'
        RemovedReason     = if ($State.RemovedReason) { "$($State.RemovedReason)" } else { $null }
        OwnerPrefix       = $OwnerPrefix
        RunStamp          = $RunStamp
        At                = $At
    }
}
