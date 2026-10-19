# Converts one item's permission array into report rows. Shared by every scan mode; the only
# difference between modes is where the permissions came from.
function ConvertTo-CIPPSharingRow {
    param($Permissions, $DriveItem, $Drive, $Site, $InternalDomains, $TenantFilter, $PassId, $RowsOut)
    foreach ($Permission in @($Permissions)) {
        # Only permissions set on the item itself; inherited ones are reported on their parent.
        if ($Permission.inheritedFrom) { continue }

        if ($Permission.link) {
            $Recipients = @($Permission.grantedToIdentitiesV2 ?? $Permission.grantedToIdentities)
            $LinkScope = $Permission.link.scope ?? 'users'
            $Classification = switch ($LinkScope) {
                'anonymous' { 'Anonymous' }
                'organization' { 'Internal' }
                'existingAccess' { 'Internal' }
                default {
                    $HasExternal = $false
                    foreach ($Recipient in $Recipients) {
                        if (Test-CIPPExternalIdentity -Identity $Recipient -InternalDomains $InternalDomains) { $HasExternal = $true; break }
                    }
                    if ($HasExternal) { 'External' } else { 'Internal' }
                }
            }
            $LinkType = $Permission.link.type ?? 'link'
            $LinkUrl = $Permission.link.webUrl
        } else {
            # Direct grant (no sharing link): only report grants to external users.
            $Recipients = @($Permission.grantedToV2 ?? $Permission.grantedTo)
            if ($Permission.roles -contains 'owner') { continue }
            $HasExternal = $false
            foreach ($Recipient in $Recipients) {
                if (Test-CIPPExternalIdentity -Identity $Recipient -InternalDomains $InternalDomains) { $HasExternal = $true; break }
            }
            if (-not $HasExternal) { continue }
            $Classification = 'External'
            $LinkScope = 'direct'
            $LinkType = 'directGrant'
            $LinkUrl = $null
        }

        $SharedWith = @($Recipients | ForEach-Object { Get-CIPPIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)

        $Id = "$($Drive.id)_$($DriveItem.id)_$($Permission.id)"
        $RowsOut.Add(@{
                PartitionKey         = $TenantFilter
                RowKey               = ([string]$Id -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')
                ScanId               = $PassId
                id                   = $Id
                siteId               = [string]$Site.SiteId
                siteName             = [string]$Site.SiteName
                siteUrl              = [string]$Site.SiteUrl
                workload             = if ($Site.IsPersonalSite) { 'OneDrive' } else { 'SharePoint' }
                driveId              = [string]$Drive.id
                driveName            = [string]$Drive.name
                itemId               = [string]$DriveItem.id
                fileName             = [string]$DriveItem.name
                itemUrl              = [string]$DriveItem.webUrl
                itemType             = if ($DriveItem.folder) { 'Folder' } else { 'File' }
                size                 = [int64]($DriveItem.size ?? 0)
                lastModifiedDateTime = if ($DriveItem.lastModifiedDateTime -is [datetime]) { $DriveItem.lastModifiedDateTime.ToUniversalTime().ToString('o') } else { [string]$DriveItem.lastModifiedDateTime }
                permissionId         = [string]$Permission.id
                linkType             = [string]$LinkType
                linkScope            = [string]$LinkScope
                classification       = [string]$Classification
                roles                = [string](ConvertTo-Json -InputObject @($Permission.roles) -Compress)
                sharedWith           = [string](ConvertTo-Json -InputObject @($SharedWith) -Compress)
                linkUrl              = [string]$LinkUrl
                hasPassword          = [bool]($Permission.hasPassword ?? $false)
                expirationDateTime   = if ($Permission.expirationDateTime -is [datetime]) { $Permission.expirationDateTime.ToUniversalTime().ToString('o') } else { [string]$Permission.expirationDateTime }
            })
    }
}
