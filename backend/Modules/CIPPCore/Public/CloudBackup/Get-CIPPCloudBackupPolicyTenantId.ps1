function Get-CIPPCloudBackupPolicyTenantId {
    <#
    .SYNOPSIS
        Resolves a cloud backup policy's stored tenant targets (AllTenants, tenants, tenant groups) to customerIds.
    .DESCRIPTION
        Only tenants present in TenantList (Get-Tenants by default) are returned, so excluded or removed tenants drop out.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Tenants,
        $TenantList
    )

    $TenantList = @($TenantList ?? (Get-Tenants))
    $Known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Tenant in $TenantList) { if ($Tenant.customerId) { [void]$Known.Add($Tenant.customerId) } }

    $Ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Groups = [System.Collections.Generic.List[object]]::new()
    foreach ($Entry in @($Tenants)) {
        switch ($Entry.type) {
            'AllTenants' { $Ids.UnionWith($Known) }
            'Tenant' { if ($Entry.customerId -and $Known.Contains($Entry.customerId)) { [void]$Ids.Add($Entry.customerId) } }
            'Group' { if ($Entry.id) { $Groups.Add([pscustomobject]@{ type = 'Group'; value = $Entry.id }) } }
        }
    }
    if ($Groups.Count -gt 0) {
        foreach ($Member in @(Expand-CIPPTenantGroups -TenantFilter $Groups.ToArray())) {
            $CustomerId = $Member.addedFields.customerId
            if ($CustomerId -and $Known.Contains($CustomerId)) { [void]$Ids.Add($CustomerId) }
        }
    }
    [string[]]@($Ids)
}
