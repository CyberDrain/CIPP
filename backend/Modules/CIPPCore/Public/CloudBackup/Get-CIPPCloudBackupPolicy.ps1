function Get-CIPPCloudBackupPolicy {
    <#
    .SYNOPSIS
        Cloud backup policies from the Config table, with their JSON columns parsed.
    .DESCRIPTION
        With -IncludePermissionStatus, PermissionStatus holds the per-tenant grant status (customerId -> { Status; Message; CheckedAt })
        from the CloudBackupPermissions table.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [switch]$IncludePermissionStatus
    )

    $Filter = "PartitionKey eq 'CloudBackupPolicy'"
    if ($Id) {
        $Guid = $Id -as [guid]
        if (-not $Guid) { return }
        $Filter = "$Filter and RowKey eq '$Guid'"
    }

    $Table = Get-CIPPTable -TableName 'Config'
    $PermissionTable = if ($IncludePermissionStatus) { Get-CIPPTable -TableName 'CloudBackupPermissions' }
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)) {
        if ($null -eq $Row) { continue }
        $NextRuns = [ordered]@{}
        if ($Row.NextRuns) {
            $ParsedRuns = [CIPP.CippJson]::ConvertFromJson([string]$Row.NextRuns)
            foreach ($Property in $ParsedRuns.PSObject.Properties) {
                $NextRuns[$Property.Name] = if ($Property.Value -is [datetime]) { $Property.Value.ToUniversalTime().ToString('o') } else { "$($Property.Value)" }
            }
        }
        $Exclusions = if ($Row.Exclusions) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Exclusions) }
        $PermissionStatus = $null
        if ($IncludePermissionStatus) {
            $PermissionStatus = @{}
            foreach ($Permission in @(Get-CIPPAzDataTableEntity @PermissionTable -Filter "PartitionKey eq '$($Row.RowKey)'")) {
                $PermissionStatus["$($Permission.RowKey)"] = [pscustomobject]@{
                    Status    = "$($Permission.Status)"
                    Message   = if ($Permission.Message) { "$($Permission.Message)" } else { $null }
                    CheckedAt = if ($Permission.CheckedAt) { "$($Permission.CheckedAt)" } else { $null }
                }
            }
        }
        [pscustomobject]@{
            Id               = $Row.RowKey
            Name             = $Row.Name
            Enabled          = "$($Row.Enabled)" -eq 'True'
            DestinationId    = $Row.DestinationId
            Tenants          = @(if ($Row.Tenants) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Tenants) })
            Workloads        = [string[]]@(if ($Row.Workloads) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Workloads) })
            Schedules        = if ($Row.Schedules) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Schedules) } else { [pscustomobject]@{} }
            NextRuns         = [pscustomobject]$NextRuns
            Exclusions       = [pscustomobject]@{
                Users  = [string[]]@($Exclusions.Users).Where({ $_ })
                Groups = [string[]]@($Exclusions.Groups).Where({ $_ })
                Sites  = [string[]]@($Exclusions.Sites).Where({ $_ })
            }
            RetentionDays    = ($Row.RetentionDays -as [int]) ?? 90
            Encryption       = "$($Row.Encryption)" -eq 'True'
            CurrentKeyId     = "$($Row.CurrentKeyId)"
            KeyIds           = @(if ($Row.KeyIds) { [CIPP.CippJson]::ConvertFromJson([string]$Row.KeyIds) })
            PermissionStatus = $PermissionStatus
            LastPrunedAt     = if ($Row.LastPrunedAt) { "$($Row.LastPrunedAt)" } else { $null }
            PruneStatus      = if ($Row.PruneStatus) { "$($Row.PruneStatus)" } else { $null }
            PruneError       = if ($Row.PruneError) { "$($Row.PruneError)" } else { $null }
            PruneSkipped     = ($Row.PruneSkipped -as [int]) ?? 0
        }
    }
}
