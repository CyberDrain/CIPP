function Push-DBCacheOneDriveRootPermissionsBatch {
    <#
    .SYNOPSIS
        Collects OneDrive root permissions for a batch of personal sites.

    .DESCRIPTION
        Processes up to 20 personal site seeds per activity. Each site is wrapped in its own
        try/catch so a batch of N sites always returns exactly N cache row objects.

        Six permission paths are indexed into permissionsJson (a pre-serialized JSON string):
        SiteAdmin, SiteRoleGroup, WebRoleAssignment, LibraryRoleAssignment, DriveRootGrant,
        DriveRootLink. Groups are stored as principals and are not expanded to users.

        collectionStatus:
        - Full     — all SPO REST paths and Graph drive root permissions succeeded
        - Skipped  — drive/owner resolution failed, SPO or Graph collection failed, or unexpected error;
                      permissionsJson = '[]'. Push-StoreOneDriveRootPermissions may replace Skipped rows
                      with prior Full cache data (merge-on-Skip) before the tenant write.

        hasNonStandardAccess is nullable ($true | $false | $null). Use -eq $true / -eq $false;
        never truthy checks. $null on batch Skipped rows; after merge-on-Skip at store, merged sites
        retain prior hasNonStandardAccess from the cached Full row.

        Test-CIPPOneDriveOwnerPrincipal compares grants to the provisioned owner (drive.owner.user.id):
        principalObjectId match, principalUpn -ieq, or LoginName claim suffix -ieq owner UPN.

        Dedup inside permissionsJson:
        - WebRoleAssignment: skip Member.Id matching associated Owner/Member/Visitor group Ids
        - LibraryRoleAssignment: only when HasUniqueRoleAssignments is true
        - DriveRootGrant: skip siteGroup.displayName matching associated group Title (case-insensitive);
          skip implicit owner grant (roles contains 'owner' + Test-CIPPOneDriveOwnerPrincipal)
        - Intentional cross-path duplicates remain (e.g. same user on SiteAdmin and SiteRoleGroup)

        Graph root permissions: skip inheritedFrom; paginate via New-GraphGetRequest; DriveRootGrant
        and named DriveRootLink recipients emit one grant per person; anonymous DriveRootLink
        emits one grant per permission.id.

        Anonymous DriveRootLink shape: principalType=Link, sharedWith=@(), linkScope/linkType populated.

        Consumer notes:
        - Grant paths != effective access (security groups need Entra membership join)
        - Unprovisioned OneDrives absent from getAllSites
        - Batch Skipped rows have permissionsJson = '[]' and hasNonStandardAccess $null; after store,
          merge-on-Skip may replace them with prior Full rows — query the cache, not batch output
        - Count DriveRootLink sharing links by distinct permissionId, not grant row count (named
          recipients share the same permissionId across multiple grant rows)
        - Child folder/file sharing is out of scope (SharePointSharingLinks cache)
        - Localized/renamed group titles may miss siteGroup dedup (grant retained, warning logged)

        Never uses User Information List fallback.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $BatchNumber = $Item.BatchNumber
    $SiteSeeds = @($Item.Sites)

    $SiteRows = [System.Collections.Generic.List[object]]::new()

    try {
        Write-Information "Processing OneDrive root permissions batch $BatchNumber for tenant $TenantFilter with $($SiteSeeds.Count) sites"

        foreach ($SiteSeed in $SiteSeeds) {
            try {
                $SiteRows.Add((Get-CIPPOneDriveSiteRow -SiteSeed $SiteSeed -TenantFilter $TenantFilter))
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: unexpected site error for '$($SiteSeed.webUrl)': $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
                $SiteRows.Add((New-CIPPOneDriveSkippedSiteRow -SiteSeed $SiteSeed -CollectionError $_.Exception.Message))
            }
        }

        if ($SiteRows.Count -ne $SiteSeeds.Count) {
            throw "Batch $BatchNumber invariant violated: expected $($SiteSeeds.Count) site rows, got $($SiteRows.Count)"
        }

        return [PSCustomObject]@{
            BatchNumber = $BatchNumber
            Sites       = @($SiteRows)
        }

    } catch {
        $ErrorMsg = "Failed OneDrive root permissions batch $BatchNumber for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
