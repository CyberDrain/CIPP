function Set-CIPPDBCacheGroups {
    <#
    .SYNOPSIS
        Caches all groups for a tenant

    .PARAMETER TenantFilter
        The tenant to cache groups for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching groups' -sev Debug

        $MemberBatchSize = 50
        $GroupSelect = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,onPremisesSyncEnabled,assignedLicenses,licenseProcessingState'
        $GroupUri = "https://graph.microsoft.com/beta/groups?`$top=999&`$select=$GroupSelect&`$expand=owners(`$select=id,displayName,userPrincipalName)"

        # Stream groups in batches of $MemberBatchSize so peak memory is one batch of rows
        # plus their member lists, not the whole tenant. The writer is opened before the
        # pipeline on purpose: GetSteppablePipeline() captures whichever scope is live, so
        # opening it inside ForEach-Object captures the Graph call's scope, which is gone
        # by End() - the end block then fails with "is not recognized".
        $CachedCount = 0
        $PendingBatch = [System.Collections.Generic.List[object]]::new()
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)

        try {
            New-GraphGetRequest -uri $GroupUri -tenantid $TenantFilter -Stream | ForEach-Object {
                $PendingBatch.Add($_)
                if ($PendingBatch.Count -ge $MemberBatchSize) {
                    Write-CIPPDBCacheGroupBatch -TenantFilter $TenantFilter -Batch $PendingBatch -PipelineWriter $Writer -Count ([ref]$CachedCount)
                }
            }

            Write-CIPPDBCacheGroupBatch -TenantFilter $TenantFilter -Batch $PendingBatch -PipelineWriter $Writer -Count ([ref]$CachedCount)

            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedCount groups with members and owners successfully" -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache groups: $($_.Exception.Message)" -sev Error
    }
}
