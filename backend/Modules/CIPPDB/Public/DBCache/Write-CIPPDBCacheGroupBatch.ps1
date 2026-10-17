function Write-CIPPDBCacheGroupBatch {
    <#
    .NOTES
        Permission: Graph | GET /groups/{id}/members | Delegated | GroupMember.ReadBasic.All | Directory.Read.All, Group.Read.All, Group.ReadBasic.All, Group.ReadWrite.All, GroupMember.Read.All, GroupMember.ReadWrite.All
    #>
    param(
        [string]$TenantFilter,
        [System.Collections.Generic.List[object]]$Batch,
        $PipelineWriter,
        [ref]$Count
    )

    if ($Batch.Count -eq 0) { return }

    $MemberRequests = $Batch | ForEach-Object {
        if ($_.id -and $_.groupTypes -notcontains 'DynamicMembership') {
            [PSCustomObject]@{
                id     = $_.id
                method = 'GET'
                url    = "/groups/$($_.id)/members?`$top=999&`$select=id,displayName,userPrincipalName"
            }
        }
    }

    $MembersByGroupId = @{}
    if ($MemberRequests) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching group members for batch of $($Batch.Count)" -sev Debug
        $MemberResults = New-GraphBulkRequest -Requests @($MemberRequests) -tenantid $TenantFilter
        foreach ($Result in $MemberResults) {
            if ($Result.id) { $MembersByGroupId[$Result.id] = $Result.body.value }
        }
        $MemberResults = $null
    }

    foreach ($Group in $Batch) {
        $groupType = if ($Group.groupTypes -contains 'Unified') { 'Microsoft 365' }
        elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'Mail-Enabled Security' }
        elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'Security' }
        elseif ([string]::IsNullOrEmpty($Group.groupTypes) -and $Group.mailEnabled -and -not $Group.securityEnabled) { 'Distribution List' }
        else { 'Unknown' }
        $calculatedGroupType = if ($Group.groupTypes -contains 'Unified') { 'm365' }
        elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'security' }
        elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'generic' }
        elseif ([string]::IsNullOrEmpty($Group.groupTypes) -and $Group.mailEnabled -and -not $Group.securityEnabled) { 'distributionList' }
        else { 'unknown' }

        $NoteProperties = [ordered]@{}
        if ($Group.id -and $Group.groupTypes -notcontains 'DynamicMembership') {
            $NoteProperties['members'] = $MembersByGroupId[$Group.id]
            # Precompute the UPN CSV so the paged list read can stream the stored blob
            # verbatim instead of parsing every member array (heavy on 50k-member groups).
            $NoteProperties['membersCsv'] = ($MembersByGroupId[$Group.id].userPrincipalName -join ',')
        }
        if ($Group.owners) {
            $NoteProperties['ownersCsv'] = ($Group.owners.userPrincipalName -join ',')
        }
        # Set unconditionally (unlike ownersCsv above) so a genuinely owner-less group
        # still gets an explicit false baked into the blob - the AsRawJson paged read
        # streams this stored blob verbatim and never recomputes it.
        $NoteProperties['hasOwner'] = [bool]($Group.owners -and $Group.owners.Count -gt 0)
        $NoteProperties['primDomain'] = ($Group.mail -split '@' | Select-Object -Last 1)
        $NoteProperties['teamsEnabled'] = ($Group.resourceProvisioningOptions -contains 'Team')
        $NoteProperties['dynamicGroupBool'] = ($Group.groupTypes -contains 'DynamicMembership')
        $NoteProperties['groupType'] = $groupType
        $NoteProperties['calculatedGroupType'] = $calculatedGroupType

        # Same as Add-Member -Force without its pipeline: half the allocation per row
        $Props = $Group.PSObject.Properties
        foreach ($Name in $NoteProperties.Keys) { $Props.Remove($Name); $Props.Add([psnoteproperty]::new($Name, $NoteProperties[$Name])) }
        $Count.Value++
        $PipelineWriter.Process($Group)
    }

    $Batch.Clear()
    $MembersByGroupId = $null
}
