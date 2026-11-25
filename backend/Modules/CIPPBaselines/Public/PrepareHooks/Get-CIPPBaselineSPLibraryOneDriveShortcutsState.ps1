function Get-CIPPBaselineSPLibraryOneDriveShortcutsState {
    <#
    .SYNOPSIS
        Prepare hook for SPLibraryOneDriveShortcuts: users who can open a library on the configured
        site but have no OneDrive shortcut into it.
    .DESCRIPTION
        Grants come from the SharePointPermissions cache: a library with its own permissions uses its
        library rows, every other library uses the site rows. Limited Access rows are ignored.
        SharePoint groups are expanded with one REST read per group, Entra and Microsoft 365 groups
        with one batched transitive members (or owners) read, and Everyone / Everyone except external
        users only when includeTenantWide is on. The site's libraries and their drive ids come from
        one Graph read. Existing shortcuts come from the OneDriveLibraryShortcuts cache; a user with
        any shortcut into a library's drive is compliant for it, and a user missing from that cache
        has no OneDrive and is skipped. The permissions scan is started when it is missing or older
        than 24 hours.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Variables = $Item.Variables
    $SiteSetting = "$($Variables.siteUrl.value ?? $Variables.siteUrl)".Trim().TrimEnd('/')
    if (-not $SiteSetting) { return @{ Current = $null; NoDataReason = 'no site URL or path is configured'; ConfigError = $true } }
    $ParentPath = if ("$($Variables.destination.value ?? $Variables.destination)" -eq 'root') { 'root' } else { 'special/shortcuts' }
    $IncludeTenantWide = $Variables.includeTenantWide -eq $true
    $ExcludedLibraries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Entry in @($Variables.excludeLibraries)) {
        $Name = "$($Entry.value ?? $Entry)".Trim()
        if ($Name) { [void]$ExcludedLibraries.Add($Name) }
    }
    $ExcludedUsers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Entry in @($Variables.excludeUsers)) {
        $Name = "$($Entry.value ?? $Entry)".Trim()
        if ($Name) { [void]$ExcludedUsers.Add($Name) }
    }

    $PermissionMeta = @($(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointPermissions' -TableName 'CippSharePointPermissions' -CountsOnly } catch { $null }))[0]
    if ($null -eq $PermissionMeta -or $PermissionMeta.Timestamp -lt (Get-Date).AddHours(-24)) {
        $null = Set-CIPPDBCacheSharePointPermissions -TenantFilter $TenantFilter
    }
    # ConfigError on the paths below stops the engine re-collecting the OneDrive cache, which cannot fix them.
    if ($null -eq $PermissionMeta) {
        return @{ Current = $null; NoDataReason = 'the SharePoint permissions scan had not run for this tenant. It has been started, and the site is graded on the next run'; ConfigError = $true }
    }

    $PermissionRows = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'SharePointPermissions' -TableName 'CippSharePointPermissions' -Fields 'rowType', 'siteId', 'siteName', 'siteUrl', 'scope', 'libraryId', 'principalId', 'principalType', 'loginName', 'isSystemManaged', 'collectionStatus', 'collectionError')
    $SitePath = if ($SiteSetting -match '^https?://') { $null } else { '/' + [uri]::UnescapeDataString($SiteSetting).TrimStart('/') }
    $SiteRow = $null
    foreach ($Row in $PermissionRows) {
        if ($Row.rowType -ne 'Site' -or -not $Row.siteUrl) { continue }
        $RowUrl = "$($Row.siteUrl)".TrimEnd('/')
        $IsMatch = if ($SitePath) { [uri]::UnescapeDataString(([uri]$RowUrl).AbsolutePath).TrimEnd('/') -eq $SitePath } else { $RowUrl -eq $SiteSetting }
        if ($IsMatch) { $SiteRow = $Row; break }
    }
    if (-not $SiteRow) { return @{ Current = $null; NoDataReason = "the site $SiteSetting was not found in the SharePoint permissions scan. Check the URL, or wait for the next scan if the site is new"; ConfigError = $true } }
    if ($SiteRow.collectionStatus -ne 'Full') { return @{ Current = $null; NoDataReason = "SharePoint permissions could not be read for $($SiteRow.siteUrl): $($SiteRow.collectionError)"; ConfigError = $true } }

    $SiteIdParts = "$($SiteRow.siteId)" -split ','
    $SiteUrl = "$($SiteRow.siteUrl)".TrimEnd('/')
    $SiteName = if ($SiteRow.siteName) { "$($SiteRow.siteName)" } else { [uri]::UnescapeDataString(([uri]$SiteUrl).Segments[-1]).TrimEnd('/') }

    $SiteGrants = [System.Collections.Generic.List[object]]::new()
    $LibraryGrants = @{}
    $SharePointGroupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Row in $PermissionRows) {
        if ($Row.rowType -ne 'Assignment' -or $Row.siteId -ne $SiteRow.siteId) { continue }
        $Grants = $SiteGrants
        if ($Row.scope -eq 'Library') {
            $ListKey = "$($Row.libraryId)".ToLowerInvariant()
            if (-not $LibraryGrants.ContainsKey($ListKey)) { $LibraryGrants[$ListKey] = [System.Collections.Generic.List[object]]::new() }
            $Grants = $LibraryGrants[$ListKey]
        }
        if ($Row.isSystemManaged -eq $true -or -not $Row.loginName) { continue }
        $Grants.Add($Row)
        if ($Row.principalType -eq 'SharePoint Group') { [void]$SharePointGroupIds.Add("$($Row.principalId)") }
    }

    $LoginsBySharePointGroup = @{}
    if ($SharePointGroupIds.Count -gt 0) {
        $Scope = "$(([uri]$SiteUrl).GetLeftPart([System.UriPartial]::Authority))/.default"
        foreach ($GroupId in $SharePointGroupIds) {
            try {
                $Members = @(New-GraphGetRequest -uri "$SiteUrl/_api/web/sitegroups/getbyid($GroupId)/users?`$select=LoginName" -tenantid $TenantFilter -scope $Scope -extraHeaders @{ Accept = 'application/json;odata=nometadata' } -UseCertificate -AsApp $true)
            } catch {
                return @{ Current = $null; NoDataReason = "the members of SharePoint group $GroupId on $SiteUrl could not be read: $($_.Exception.Message)"; ConfigError = $true }
            }
            $LoginsBySharePointGroup[$GroupId] = @(foreach ($Member in $Members) { if ($Member.LoginName) { "$($Member.LoginName)" } })
        }
    }

    try {
        $Drives = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$($SiteRow.siteId)/drives?`$select=id,name,sharePointIds" -tenantid $TenantFilter -asapp $true)
    } catch {
        return @{ Current = $null; NoDataReason = "the document libraries of $SiteUrl could not be listed: $($_.Exception.Message)"; ConfigError = $true }
    }

    # Each library's grants flattened to login names, SharePoint groups replaced by their members.
    $Libraries = [System.Collections.Generic.List[object]]::new()
    $AllLogins = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Drive in $Drives) {
        $ListId = "$($Drive.sharePointIds.listId)".ToLowerInvariant()
        if (-not $Drive.id -or -not $ListId -or $ExcludedLibraries.Contains("$($Drive.name)")) { continue }
        $Grants = if ($LibraryGrants.ContainsKey($ListId)) { $LibraryGrants[$ListId] } else { $SiteGrants }
        $Logins = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Grant in $Grants) {
            $GrantLogins = if ($Grant.principalType -eq 'SharePoint Group') { $LoginsBySharePointGroup["$($Grant.principalId)"] } else { @("$($Grant.loginName)") }
            foreach ($Login in $GrantLogins) {
                [void]$Logins.Add($Login)
                [void]$AllLogins.Add($Login)
            }
        }
        $Libraries.Add([PSCustomObject]@{ Drive = $Drive; ListId = $ListId; Logins = $Logins })
    }

    $UpnsByLogin = @{}
    $TenantWideLogins = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $GroupRequests = [System.Collections.Generic.List[hashtable]]::new()
    $RequestIdByLogin = @{}
    foreach ($Login in $AllLogins) {
        if ($Login -match '^i:0#\.f\|membership\|(?<upn>[^|]+)$') {
            $UpnsByLogin[$Login] = @($Matches['upn'])
        } elseif ($Login -match '^c:0t\.c\|tenant\|(?<id>[0-9a-fA-F-]{36})$') {
            $RequestIdByLogin[$Login] = "members-$($Matches['id'])"
        } elseif ($Login -match '^c:0o\.c\|federateddirectoryclaimprovider\|(?<id>[0-9a-fA-F-]{36})(?<owners>_o)?$') {
            $RequestIdByLogin[$Login] = if ($Matches['owners']) { "owners-$($Matches['id'])" } else { "members-$($Matches['id'])" }
        } elseif ($Login -match '^c:0\(\.s\|true$|^c:0-\.f\|rolemanager\|spo-grid-all-users/|^c:0!\.s\|windows$') {
            [void]$TenantWideLogins.Add($Login)
        }
    }
    $RequestIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($RequestId in $RequestIdByLogin.Values) {
        if (-not $RequestIds.Add($RequestId)) { continue }
        $Kind, $GroupId = $RequestId -split '-', 2
        $Relation = if ($Kind -eq 'owners') { 'owners' } else { 'transitiveMembers' }
        $GroupRequests.Add(@{ id = $RequestId; method = 'GET'; url = "groups/$GroupId/$Relation/microsoft.graph.user?`$select=userPrincipalName&`$top=999" })
    }
    $UpnsByRequestId = @{}
    if ($GroupRequests.Count -gt 0) {
        try {
            $Responses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($GroupRequests) -asapp $true -Version 'v1.0')
        } catch {
            return @{ Current = $null; NoDataReason = "the group membership lookup failed: $($_.Exception.Message)"; ConfigError = $true }
        }
        foreach ($Response in $Responses) {
            $Status = [int]$Response.status
            # A group deleted in Entra can still hold a SharePoint grant; it has no members to add.
            if ($Status -eq 404) { $UpnsByRequestId["$($Response.id)"] = @(); continue }
            if ($Status -lt 200 -or $Status -gt 299) {
                return @{ Current = $null; NoDataReason = "the group membership lookup returned $Status for $($Response.id)"; ConfigError = $true }
            }
            $UpnsByRequestId["$($Response.id)"] = @(foreach ($Member in @($Response.body.value)) { if ($Member.userPrincipalName) { "$($Member.userPrincipalName)" } })
        }
    }
    foreach ($Login in $RequestIdByLogin.Keys) { $UpnsByLogin[$Login] = $UpnsByRequestId[$RequestIdByLogin[$Login]] }

    $UserByUpn = @{}
    foreach ($User in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'userPrincipalName', 'accountEnabled', 'userType')) {
        if ($User.accountEnabled -ne $true -or $User.userType -ne 'Member' -or -not $User.id -or [string]::IsNullOrWhiteSpace($User.userPrincipalName)) { continue }
        if ($ExcludedUsers.Contains("$($User.userPrincipalName)")) { continue }
        $UserByUpn["$($User.userPrincipalName)".ToLowerInvariant()] = $User
    }

    $ShortcutRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OneDriveLibraryShortcuts').Where({ $_ })
    if ($ShortcutRows.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'OneDriveLibraryShortcuts')) {
        return @{ Current = $null; NoDataReason = 'the OneDrive library shortcuts cache could not be collected for this tenant' }
    }
    $DriveIdsByUserId = @{}
    foreach ($Row in $ShortcutRows) {
        $DriveIdsByUserId["$($Row.id)"] = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Row.driveIds), [System.StringComparer]::Ordinal)
    }

    $Offenders = [System.Collections.Generic.List[string]]::new()
    $Targets = [System.Collections.Generic.List[object]]::new()
    $InvalidNameCharacters = '["*:<>?/\\|]'
    foreach ($Library in $Libraries) {
        $Upns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $TenantWide = $false
        foreach ($Login in $Library.Logins) {
            if ($TenantWideLogins.Contains($Login)) { $TenantWide = $true; continue }
            foreach ($Upn in @($UpnsByLogin[$Login])) { if ($Upn) { [void]$Upns.Add($Upn) } }
        }
        if ($TenantWide -and $IncludeTenantWide) {
            foreach ($Upn in $UserByUpn.Keys) { [void]$Upns.Add($Upn) }
        } elseif ($TenantWide) {
            Write-Information "Baselines: SPLibraryOneDriveShortcuts on $TenantFilter - $SiteUrl library $($Library.Drive.name) is shared with everyone; only its named grants get shortcuts."
        }
        $ShortcutName = ("$SiteName - $($Library.Drive.name)" -replace $InvalidNameCharacters, '-').Trim().TrimEnd('.')
        foreach ($Upn in $Upns) {
            $User = $UserByUpn[$Upn.ToLowerInvariant()]
            if (-not $User) { continue }
            $DriveIds = $DriveIdsByUserId["$($User.id)"]
            if ($null -eq $DriveIds -or $DriveIds.Contains("$($Library.Drive.id)")) { continue }
            $Offenders.Add("$($User.userPrincipalName): $($Library.Drive.name)")
            $Targets.Add([PSCustomObject]@{
                    userId            = "$($User.id)"
                    userPrincipalName = "$($User.userPrincipalName)"
                    parentPath        = $ParentPath
                    shortcutName      = $ShortcutName
                    spListId          = $Library.ListId
                    spSiteId          = $SiteIdParts[1]
                    spWebId           = $SiteIdParts[2]
                    spSiteUrl         = $SiteUrl
                })
        }
    }
    $Offenders.Sort([System.StringComparer]::OrdinalIgnoreCase)

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offenders)
            targets   = @($Targets)
        }
    }
}
