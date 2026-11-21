function Get-CIPPCloudBackupUnusedPermission {
    <#
    .SYNOPSIS
        Tenants where cloud backup granted CIPP's app permissions that no cloud backup policy needs any more.
    .DESCRIPTION
        Returns { TenantId; GrantedAt; RoleIds; Permissions } for each tenant that no policy backs up. RoleIds are the roles cloud
        backup added there, without those in CIPP's own permission set, which a revoke keeps. With TenantId, only that tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId
    )

    $Table = Get-CIPPTable -TableName 'CloudBackupPermissions'
    $Filter = "PartitionKey eq 'GrantedRoles'"
    if ($TenantId) { $Filter = "$Filter and RowKey eq '$TenantId'" }
    $Records = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
    if ($Records.Count -eq 0) { return }

    $TenantList = @(Get-Tenants)
    $Known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Tenant in $TenantList) { if ($Tenant.customerId) { [void]$Known.Add($Tenant.customerId) } }
    $Covered = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Policy in @(Get-CIPPCloudBackupPolicy)) {
        foreach ($Id in @(Get-CIPPCloudBackupPolicyTenantId -Tenants $Policy.Tenants -TenantList $TenantList)) { [void]$Covered.Add($Id) }
    }

    $Kept = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Permission in @((Get-CippSamPermissions -NoDiff).Permissions.'00000003-0000-0000-c000-000000000000'.applicationPermissions)) {
        if ($Permission.id) { [void]$Kept.Add("$($Permission.id)") }
    }
    $Names = @{}
    foreach ($Role in Get-CIPPCloudBackupPermissionRole) { $Names[$Role.Id] = $Role.Name }

    foreach ($Record in $Records) {
        if (-not $Known.Contains("$($Record.RowKey)") -or $Covered.Contains("$($Record.RowKey)")) { continue }
        $RoleIds = @(foreach ($RoleId in @(if ($Record.RoleIds) { [CIPP.CippJson]::ConvertFromJson([string]$Record.RoleIds) })) {
                if ($RoleId -and -not $Kept.Contains("$RoleId")) { "$RoleId" }
            })
        [pscustomobject]@{
            TenantId    = "$($Record.RowKey)"
            GrantedAt   = "$($Record.GrantedAt)"
            RoleIds     = $RoleIds
            Permissions = @(foreach ($RoleId in $RoleIds) { $Names[$RoleId] ?? $RoleId })
        }
    }
}
