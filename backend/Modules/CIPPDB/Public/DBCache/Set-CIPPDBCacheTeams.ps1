function Set-CIPPDBCacheTeams {
    <#
    .NOTES
        Permission: Graph | GET /groups | Delegated | Group.ReadBasic.All | Directory.Read.All, Directory.ReadWrite.All, Group-PreferredDataLocation.ReadWrite.All, Group.ManageProtection.All, Group.Read.All, Group.ReadWrite.All, GroupMember.Read.All
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams list' -sev Debug

        # Streamed straight into the writer: the rows are read back from table storage in RowKey
        # order, so sorting here never reached a consumer (Get-CIPPTeamsReport re-sorts by
        # displayName itself on the AllTenants path). Sort-Object is also fully blocking, so it
        # held every team in memory and defeated streaming.
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName,description,visibility,mailNickname" -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Teams' -AddCount
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams list: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
