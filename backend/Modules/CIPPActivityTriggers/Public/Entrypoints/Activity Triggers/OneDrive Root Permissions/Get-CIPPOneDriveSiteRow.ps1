function Get-CIPPOneDriveSiteRow {
    <#
    .NOTES
        Permission: Graph | GET /sites/{id}/drive | Application | Files.Read.All | Files.ReadWrite.All
        Permission: Graph | GET /sites/{id}/drive/root/permissions | Application | Sites.FullControl.All
        Permission: Graph | GET /users/{id} | Application | User.Read.All | User.ReadWrite.All, Directory.Read.All, Directory.ReadWrite.All
    #>
    param($SiteSeed, $TenantFilter)

    $SiteId = $SiteSeed.id
    $SiteUrl = $SiteSeed.webUrl
    $SiteDisplayName = $SiteSeed.displayName
    $CollectedAt = (Get-Date).ToUniversalTime().ToString('o')

    $Drive = $null
    try {
        $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drive?`$select=id,owner,webUrl,sharepointIds" -tenantid $TenantFilter -asapp $true
    } catch {
        return (New-CIPPOneDriveSkippedSiteRow -SiteSeed $SiteSeed -CollectionError "Drive resolution failed: $($_.Exception.Message)")
    }

    if (-not $Drive -or -not $Drive.id) {
        return (New-CIPPOneDriveSkippedSiteRow -SiteSeed $SiteSeed -CollectionError 'Drive resolution returned no drive')
    }

    $OwnerObjectId = $Drive.owner.user.id
    $OwnerDisplayName = $Drive.owner.user.displayName
    $OwnerPrincipalName = $Drive.owner.user.userPrincipalName ?? $Drive.owner.user.email
    if (-not $OwnerPrincipalName -and $OwnerObjectId) {
        try {
            $OwnerUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($OwnerObjectId)?`$select=userPrincipalName" -tenantid $TenantFilter -asapp $true
            $OwnerPrincipalName = $OwnerUser.userPrincipalName
        } catch {
            $OwnerPrincipalName = $null
        }
    }

    $DriveId = $Drive.id
    $DriveWebUrl = $Drive.webUrl
    $LibraryId = $Drive.sharepointIds.listId
    $LibraryHasUniquePermissions = $false
    $LibraryTitle = $null

    $SpoGrants = [System.Collections.Generic.List[object]]::new()
    $AssociatedGroupIds = [System.Collections.Generic.HashSet[string]]::new()
    $AssociatedGroupTitles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    try {
        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Scope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri

        $AssociatedEndpoints = [ordered]@{
            'Owners'   = 'associatedownergroup'
            'Members'  = 'associatedmembergroup'
            'Visitors' = 'associatedvisitorgroup'
        }
        foreach ($RoleName in $AssociatedEndpoints.Keys) {
            $GroupEntity = New-GraphGetRequest -uri "$BaseUri/web/$($AssociatedEndpoints[$RoleName])?`$select=Id,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            if ($GroupEntity.Id) {
                [void]$AssociatedGroupIds.Add([string]$GroupEntity.Id)
                if ($GroupEntity.Title) { [void]$AssociatedGroupTitles.Add([string]$GroupEntity.Title) }
            }
        }

        $SiteAdmins = @(New-GraphGetRequest -uri "$BaseUri/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,Email,LoginName,PrincipalType,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
        foreach ($Admin in $SiteAdmins) {
            $SpoGrants.Add((New-CIPPSpoUserGrant -User $Admin -PermissionSource 'SiteAdmin' -Group 'Site Admins' -IsSiteAdmin $true))
        }

        foreach ($RoleName in $AssociatedEndpoints.Keys) {
            $Users = @(New-GraphGetRequest -uri "$BaseUri/web/$($AssociatedEndpoints[$RoleName])/users?`$select=Id,Title,Email,LoginName,PrincipalType,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
            foreach ($User in $Users) {
                $SpoGrants.Add((New-CIPPSpoUserGrant -User $User -PermissionSource 'SiteRoleGroup' -Group $RoleName))
            }
        }

        $WebAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
        foreach ($Assignment in $WebAssignments) {
            if ($Assignment.Member.Id -and $AssociatedGroupIds.Contains([string]$Assignment.Member.Id)) { continue }
            foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                $SpoGrants.Add((New-CIPPSpoRoleAssignmentGrant -Member $Assignment.Member -RoleBinding $Binding -PermissionSource 'WebRoleAssignment'))
            }
        }

        if ($LibraryId) {
            $ListInfo = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$LibraryId')?`$select=HasUniqueRoleAssignments,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            $LibraryHasUniquePermissions = [bool]$ListInfo.HasUniqueRoleAssignments
            $LibraryTitle = $ListInfo.Title
            if ($LibraryHasUniquePermissions) {
                $LibraryAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$LibraryId')/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                foreach ($Assignment in $LibraryAssignments) {
                    if ($Assignment.Member.Id -and $AssociatedGroupIds.Contains([string]$Assignment.Member.Id)) { continue }
                    foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                        $SpoGrants.Add((New-CIPPSpoRoleAssignmentGrant -Member $Assignment.Member -RoleBinding $Binding -PermissionSource 'LibraryRoleAssignment' -LibraryTitle $LibraryTitle))
                    }
                }
            }
        }

    } catch {
        $SpoError = $_.Exception.Message
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: SPO collection failed for '$SiteUrl': $SpoError" -sev Warning
        return (New-CIPPOneDriveSkippedSiteRow -SiteSeed $SiteSeed -CollectionError "SPO collection failed: $SpoError")
    }

    $GraphGrants = [System.Collections.Generic.List[object]]::new()
    $InheritedSkipCount = 0
    try {
        $Permissions = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drive/root/permissions" -tenantid $TenantFilter -asapp $true)
        foreach ($Permission in $Permissions) {
            if ($Permission.inheritedFrom) {
                $InheritedSkipCount++
                continue
            }

            if ($Permission.link) {
                $Recipients = @($Permission.grantedToIdentitiesV2 ?? $Permission.grantedToIdentities ?? @())
                $SharedWith = @($Recipients | ForEach-Object { Get-CIPPGraphIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)
                $LinkProps = @{
                    linkScope          = $Permission.link.scope ?? 'users'
                    linkType           = $Permission.link.type ?? 'view'
                    linkUrl            = $Permission.link.webUrl
                    hasPassword        = [bool]($Permission.hasPassword ?? $false)
                    expirationDateTime = $Permission.expirationDateTime
                }
                if ($Recipients.Count -eq 0) {
                    $GraphGrants.Add([PSCustomObject]@{
                            permissionSource     = 'DriveRootLink'
                            group                = $null
                            principalId          = [string]$Permission.id
                            principalObjectId    = $null
                            principalUpn         = $null
                            principalDisplayName = $null
                            principalLoginName   = $null
                            principalEmail       = $null
                            principalType        = 'Link'
                            permissionLevel      = $null
                            roleDefinitionId     = $null
                            roles                = @($Permission.roles)
                            isSiteAdmin          = $false
                            isGuest              = $false
                            permissionId         = [string]$Permission.id
                            linkScope            = $LinkProps.linkScope
                            linkType             = $LinkProps.linkType
                            linkUrl              = $LinkProps.linkUrl
                            hasPassword          = $LinkProps.hasPassword
                            expirationDateTime   = $LinkProps.expirationDateTime
                            sharedWith           = @()
                            libraryTitle         = $null
                        })
                } else {
                    foreach ($Recipient in $Recipients) {
                        $GraphGrants.Add((New-CIPPGraphIdentityGrant -Identity $Recipient -PermissionSource 'DriveRootLink' -PermissionId $Permission.id -Roles @($Permission.roles) -SharedWith $SharedWith -LinkProps $LinkProps))
                    }
                }
                continue
            }

            $Recipients = @($Permission.grantedToIdentitiesV2 ?? @())
            if ($Recipients.Count -eq 0 -and $Permission.grantedToV2) {
                $Recipients = @($Permission.grantedToV2)
            }
            if ($Recipients.Count -eq 0) { continue }

            $SharedWith = @($Recipients | ForEach-Object { Get-CIPPGraphIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)
            foreach ($Recipient in $Recipients) {
                if ($Recipient.siteGroup -and $Recipient.siteGroup.displayName -and
                    $AssociatedGroupTitles.Contains([string]$Recipient.siteGroup.displayName)) {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: siteGroup dedup matched '$($Recipient.siteGroup.displayName)' on '$SiteUrl'" -sev Debug
                    continue
                }
                $Candidate = New-CIPPGraphIdentityGrant -Identity $Recipient -PermissionSource 'DriveRootGrant' -PermissionId $Permission.id -Roles @($Permission.roles) -SharedWith $SharedWith
                if ($Permission.roles -contains 'owner' -and
                    (Test-CIPPOneDriveOwnerPrincipal -Grant $Candidate -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
                    continue
                }
                $GraphGrants.Add($Candidate)
            }
        }
        if ($InheritedSkipCount -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: skipped $InheritedSkipCount inherited root permissions on '$SiteUrl'" -sev Debug
        }
    } catch {
        return (New-CIPPOneDriveSkippedSiteRow -SiteSeed $SiteSeed -CollectionError "Graph root permissions failed: $($_.Exception.Message)")
    }

    $AllGrants = @($SpoGrants) + @($GraphGrants)

    $HasNonStandardAccess = Get-CIPPOneDriveHasNonStandardAccess -Grants $AllGrants -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName -LibraryHasUniquePermissions $LibraryHasUniquePermissions -CollectionStatus 'Full'
    $PermissionsJson = if ($AllGrants.Count -gt 0) {
        ConvertTo-Json -InputObject @($AllGrants) -Compress -Depth 10
    } else {
        '[]'
    }

    [PSCustomObject]@{
        id                          = $SiteId
        siteId                      = $SiteId
        siteUrl                     = $SiteUrl
        siteDisplayName             = $SiteDisplayName
        ownerPrincipalName          = $OwnerPrincipalName
        ownerObjectId               = $OwnerObjectId
        ownerDisplayName            = $OwnerDisplayName
        driveId                     = $DriveId
        driveWebUrl                 = $DriveWebUrl
        libraryId                   = $LibraryId
        libraryHasUniquePermissions = $LibraryHasUniquePermissions
        collectionStatus            = 'Full'
        collectionError             = $null
        hasNonStandardAccess        = $HasNonStandardAccess
        permissionsJson             = $PermissionsJson
        grantCount                  = $AllGrants.Count
        collectedAt                 = $CollectedAt
    }
}
