function Expand-CIPPTenantGroups {
    <#
        .SYNOPSIS
            Expands a list of groups to their members.
        .DESCRIPTION
            This function takes a a tenant filter object and expands it to include all members of the groups.
        .EXAMPLE

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        $TenantFilter
    )
    $TenantList = $null
    $ExpandedGroups = $TenantFilter | ForEach-Object {
        $FilterValue = $_
        # Group lookup
        if ($_.type -eq 'Group') {
            # Read only when a group needs it: callers expand one list per alert rule, and most name no group.
            $TenantList ??= Get-Tenants -IncludeErrors
            $GroupResult = Get-TenantGroups -GroupId $_.value
            $members = if ($GroupResult) { $GroupResult.members } else { @() }
            $TenantList | Where-Object -Property customerId -In $members.customerId | ForEach-Object {
                $GroupMember = $_
                [PSCustomObject]@{
                    value       = $GroupMember.defaultDomainName
                    label       = $GroupMember.displayName
                    addedFields = $GroupMember | Select-Object defaultDomainName, displayName, customerId
                    type        = 'Tenant'
                }
            }
        } else {
            $FilterValue
        }
    }
    return $ExpandedGroups | Sort-Object -Property value -Unique
}
