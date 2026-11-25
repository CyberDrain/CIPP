function Set-CIPPDBCacheOneDriveLibraryShortcuts {
    <#
    .SYNOPSIS
        Caches which SharePoint libraries each enabled member already has a OneDrive shortcut into

    .DESCRIPTION
        On demand only (no collection group): the SPLibraryOneDriveShortcuts baseline collects it on a
        miss, when it is older than 3 hours and after every remediation. Writes one row per user with
        a provisioned OneDrive: id, userPrincipalName and driveIds, the sorted drive ids that the
        user's shortcuts point into. Shortcuts are read from the OneDrive root and, for users who have
        one, the Shortcuts folder, both through $batch. No shortcut or file names are stored. A user
        without a provisioned OneDrive (404) is skipped quietly. Nothing is written when every listing
        fails, so the previous verdict stands.

    .PARAMETER TenantFilter
        The tenant to cache shortcuts for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'userPrincipalName', 'accountEnabled', 'userType').Where({ $_ })
        if ($Users.Count -eq 0) {
            Set-CIPPDBCacheUsers -TenantFilter $TenantFilter
            $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'userPrincipalName', 'accountEnabled', 'userType').Where({ $_ })
        }
        if ($Users.Count -eq 0) { throw 'the Users cache is empty' }

        $Candidates = @($Users.Where({ $_.accountEnabled -eq $true -and $_.userType -eq 'Member' -and $_.id -and -not [string]::IsNullOrWhiteSpace($_.userPrincipalName) }))
        $UpnById = @{}
        $Prefer = @{ Prefer = 'Include-Feature=AddToOneDrive' }
        $RootRequests = foreach ($User in $Candidates) {
            $UpnById["$($User.id)"] = $User.userPrincipalName
            @{
                id      = "$($User.id)"
                method  = 'GET'
                url     = "users/$($User.id)/drive/root/children?`$select=id,remoteItem,specialFolder&`$top=999"
                headers = $Prefer
            }
        }
        $RootResponses = if ($Candidates.Count -gt 0) { @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RootRequests) -asapp $true) } else { @() }

        $DriveIdsByUser = @{}
        $FolderRequests = [System.Collections.Generic.List[hashtable]]::new()
        $Failures = [System.Collections.Generic.List[string]]::new()
        $Readable = 0
        foreach ($Response in $RootResponses) {
            $UserId = "$($Response.id)"
            $Status = [int]$Response.status
            if ($Status -eq 404) { continue }
            $Readable++
            if ($Status -lt 200 -or $Status -gt 299) {
                $Failures.Add("$($UpnById[$UserId]) -> $Status $($Response.body.error.message)")
                continue
            }
            $DriveIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($Child in @($Response.body.value)) {
                if ($Child.remoteItem.parentReference.driveId) { [void]$DriveIds.Add("$($Child.remoteItem.parentReference.driveId)") }
                if ($Child.specialFolder.name -eq 'shortcuts' -and $Child.id) {
                    $FolderRequests.Add(@{
                            id      = $UserId
                            method  = 'GET'
                            url     = "users/$UserId/drive/items/$($Child.id)/children?`$select=id,remoteItem&`$top=999"
                            headers = $Prefer
                        })
                }
            }
            $DriveIdsByUser[$UserId] = $DriveIds
        }

        if ($FolderRequests.Count -gt 0) {
            foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($FolderRequests) -asapp $true)) {
                $UserId = "$($Response.id)"
                $Status = [int]$Response.status
                if ($Status -lt 200 -or $Status -gt 299) {
                    # Without the folder listing this user's shortcuts are incomplete, so the user is dropped rather than graded on half the data.
                    $Failures.Add("$($UpnById[$UserId]) (Shortcuts folder) -> $Status $($Response.body.error.message)")
                    [void]$DriveIdsByUser.Remove($UserId)
                    continue
                }
                foreach ($Child in @($Response.body.value)) {
                    if ($Child.remoteItem.parentReference.driveId) { [void]$DriveIdsByUser[$UserId].Add("$($Child.remoteItem.parentReference.driveId)") }
                }
            }
        }

        if ($Failures.Count -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive library shortcuts: could not list $($Failures.Count) of $Readable OneDrives. $($Failures.GetRange(0, [Math]::Min(10, $Failures.Count)) -join ' | ')" -sev Warning
            if ($DriveIdsByUser.Count -eq 0 -and $Readable -gt 0) { throw "every OneDrive listing failed: $($Failures[0])" }
        }

        $Rows = foreach ($UserId in $DriveIdsByUser.Keys) {
            $DriveIds = [string[]]@($DriveIdsByUser[$UserId])
            [array]::Sort($DriveIds, [System.StringComparer]::Ordinal)
            [PSCustomObject]@{ id = $UserId; userPrincipalName = $UpnById[$UserId]; driveIds = $DriveIds }
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveLibraryShortcuts' -Data @($Rows) -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OneDrive library shortcuts: $($_.Exception.Message)" -sev Error
    }
}
