function Grant-CIPPCloudBackupPermission {
    <#
    .SYNOPSIS
        Grants the CIPP app the Microsoft Graph application permissions that cloud backup workloads need in one tenant.
    .DESCRIPTION
        Returns { Status = Granted | Failed; Message; CheckedAt }. Never throws. The roles it adds (not those the app already
        had) are recorded in the CloudBackupPermissions table (partition GrantedRoles), so a revoke removes only those.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string[]]$Workloads
    )

    $CheckedAt = [datetime]::UtcNow.ToString('o')
    try {
        if ($TenantFilter -eq $env:TenantID -or [bool](Get-CIPPPartnerTenant -PartnerTenantId $TenantFilter)) {
            return [pscustomobject]@{
                Status    = 'Failed'
                Message   = 'Cloud backup cannot grant permissions in a partner tenant. Add them under CIPP > Settings > Permissions instead.'
                CheckedAt = $CheckedAt
            }
        }

        $RoleIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $Wanted = @(foreach ($Workload in $Workloads) { "$Workload".ToLowerInvariant() })
        foreach ($Role in Get-CIPPCloudBackupPermissionRole) {
            if ($Role.Workloads.Where({ $Wanted -contains $_ }, 'First').Count -gt 0) { [void]$RoleIds.Add($Role.Id) }
        }
        if ($RoleIds.Count -eq 0) {
            return [pscustomobject]@{ Status = 'Granted'; Message = 'No permissions needed'; CheckedAt = $CheckedAt }
        }

        $Before = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $BeforeKnown = $false
        try {
            $ServicePrincipal = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$($env:ApplicationID)')?`$select=id" -tenantid $TenantFilter -skipTokenCache $true -NoAuthCheck $true
            foreach ($Assignment in @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ServicePrincipal.id)/appRoleAssignments?`$select=appRoleId" -tenantid $TenantFilter -skipTokenCache $true -NoAuthCheck $true)) {
                if ($Assignment.appRoleId) { [void]$Before.Add("$($Assignment.appRoleId)") }
            }
            $BeforeKnown = $true
        } catch {
            Write-Information "Cloud backup could not read the app's current roles in $($TenantFilter): $($_.Exception.Message)"
        }

        $ResourceAccess = [System.Collections.Generic.List[object]]::new()
        foreach ($RoleId in $RoleIds) { $ResourceAccess.Add(@{ id = $RoleId; type = 'Role' }) }
        $RequiredResourceAccess = @(@{ resourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = $ResourceAccess })

        $Output = @(Add-CIPPApplicationPermission -RequiredResourceAccess $RequiredResourceAccess -ApplicationId $env:ApplicationID -TenantFilter $TenantFilter)
        $Failures = @(foreach ($Line in $Output) { if ("$Line" -like 'Failed*') { "$Line" } })

        $Added = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($BeforeKnown) {
            foreach ($RoleId in $RoleIds) {
                if (-not $Before.Contains($RoleId) -and -not $Failures.Where({ $_.Contains($RoleId) }, 'First')) { [void]$Added.Add($RoleId) }
            }
        }
        if ($Added.Count -gt 0) {
            $Table = Get-CIPPTable -TableName 'CloudBackupPermissions'
            $Record = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GrantedRoles' and RowKey eq '$TenantFilter'")[0]
            if ($Record.RoleIds) { foreach ($RoleId in @([CIPP.CippJson]::ConvertFromJson([string]$Record.RoleIds))) { [void]$Added.Add("$RoleId") } }
            $AddedIds = [string[]]@($Added)
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'GrantedRoles'
                RowKey       = $TenantFilter
                RoleIds      = [CIPP.CippJson]::ToJson($AddedIds, 2) ?? (ConvertTo-Json -InputObject $AddedIds -Compress)
                GrantedAt    = $CheckedAt
            } -Force
        }
        if ($Failures.Count -gt 0) {
            return [pscustomobject]@{ Status = 'Failed'; Message = $Failures -join '; '; CheckedAt = $CheckedAt }
        }
        [pscustomobject]@{ Status = 'Granted'; Message = $null; CheckedAt = $CheckedAt }
    } catch {
        [pscustomobject]@{ Status = 'Failed'; Message = (Get-CippException -Exception $_).NormalizedError; CheckedAt = $CheckedAt }
    }
}
