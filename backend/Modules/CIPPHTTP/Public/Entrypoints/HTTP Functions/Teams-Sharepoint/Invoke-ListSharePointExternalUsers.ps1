function Invoke-ListSharePointExternalUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists external/guest users known to SharePoint from two sources: the tenant external
        users store (populated when a guest first redeems a share) and a sweep of every site's
        user list (which also catches guests who were granted membership but never signed in).
        Every entry is classified against Entra: 'Entra B2B' (live Entra guest), 'Orphaned B2B'
        (the Entra guest was deleted but SharePoint still references them) or 'SharePoint-only'
        (legacy email-authenticated guest that never had an Entra object).

        Each row also carries SiteAccess: one entry per site with the site user ID and the
        site-level guest expiration (UserExpiration from the site's User Information List),
        for use with ExecSPOGuestAccess (Extend / Expire on a single site).

        Sites that could not be enumerated or read are listed in Metadata.Warnings and the status is
        207, since guests on them are missing from the list.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    # CSOM verbose JSON dates arrive as '/Date(year,month,day,h,m,s,ms)/' with a 0-based month.
    function ConvertFrom-CsomDate($Value) {
        if ("$Value" -match '/Date\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)/') {
            return ([datetime]::new([int]$Matches[1], ([int]$Matches[2] + 1), [int]$Matches[3], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6], [System.DateTimeKind]::Utc)).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        return $Value
    }

    # Sources that could not be read; returned as Metadata.Warnings with a 207 so a partial list
    # (and a full removal built from it) is not mistaken for a complete one.
    $Warnings = [System.Collections.Generic.List[string]]::new()
    try {
        # --- Source 1: tenant external users store ---
        try {
            $StoreUsers = @(Get-CIPPSPOExternalUsers -TenantFilter $TenantFilter)
        } catch {
            throw "Could not enumerate the SharePoint external users store: $($_.Exception.Message)"
        }

        # --- Source 2: guest entries in every site's user list ---
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $VerboseHeaders = @{ Accept = 'application/json;odata=verbose' }
        # Site guest expiration is stored on the User Information List (UserExpiration);
        # list item ID == site user ID.
        $CamlBody = @{
            query = @{
                __metadata = @{ type = 'SP.CamlQuery' }
                ViewXml    = "<View><ViewFields><FieldRef Name='ID'/><FieldRef Name='UserExpiration'/></ViewFields><RowLimit>5000</RowLimit></View>"
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $SiteGuests = @{}
        $SkippedSites = [System.Collections.Generic.List[string]]::new()
        try {
            # NB: getAllSites returns an empty set when $select is combined with this $filter.
            $Sites = @((New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/getAllSites?`$filter=isPersonalSite eq false&`$top=999" -tenantid $TenantFilter -AsApp $true).webUrl) | Where-Object { $_ }
        } catch {
            $Sites = @()
            $Warnings.Add("Could not enumerate SharePoint sites, so site memberships are missing and guests who are only site members are not listed: $($_.Exception.Message)")
        }

        foreach ($SiteUrl in $Sites) {
            try {
                $Users = New-GraphGetRequest -uri "$($SiteUrl.TrimEnd('/'))/_api/web/siteusers?`$select=Id,Title,Email,LoginName,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            } catch {
                $SkippedSites.Add($SiteUrl) # sites the app cannot reach (locked etc.)
                continue
            }

            $SiteGuestUsers = @($Users | Where-Object { [bool]$_.IsShareByEmailGuestUser -or [bool]$_.IsEmailAuthenticationGuestUser -or $_.LoginName -match '(?i)#ext#|urn%3aspo%3aguest' })
            if ($SiteGuestUsers.Count -eq 0) { continue }

            # Per-site guest expiration, only fetched for sites that actually have guests.
            $ExpiryById = @{}
            try {
                # NOTE: SharePoint REST app-only POSTs need the certificate-based token; see
                # Remove-CIPPSPOSiteUser for the POST mechanism used for SharePoint REST writes.
                $Resp = New-GraphPOSTRequest -uri "$($SiteUrl.TrimEnd('/'))/_api/web/SiteUserInfoList/GetItems" -tenantid $TenantFilter -scope $Scope -AsApp $true -UseCertificate -type 'POST' -body $CamlBody -contentType 'application/json;odata=verbose' -AddedHeaders $VerboseHeaders
                $Items = if ($Resp.d.results) { $Resp.d.results } elseif ($Resp.value) { $Resp.value } else { @($Resp) }
                foreach ($Item in $Items) {
                    if ($Item.ID) { $ExpiryById[[int]$Item.ID] = $Item.UserExpiration }
                }
            } catch {
                Write-Information "Could not read guest expiration for $($SiteUrl): $($_.Exception.Message)"
            }

            foreach ($User in $SiteGuestUsers) {
                $Key = ($User.LoginName -split '\|')[-1].ToLower()
                if (-not $SiteGuests.ContainsKey($Key)) {
                    $SiteGuests[$Key] = [PSCustomObject]@{
                        Title      = $User.Title
                        Email      = $User.Email
                        LoginName  = $User.LoginName
                        Sites      = [System.Collections.Generic.List[string]]::new()
                        SiteAccess = [System.Collections.Generic.List[object]]::new()
                    }
                }
                [void]$SiteGuests[$Key].Sites.Add($SiteUrl)
                $Expiry = $ExpiryById[[int]$User.Id]
                $SiteGuests[$Key].SiteAccess.Add([PSCustomObject]@{
                        SiteUrl    = $SiteUrl
                        SiteUserId = [int]$User.Id
                        Expiration = if ($Expiry) { $Expiry } else { $null } # null = no expiry set
                    })
            }
        }

        if ($SkippedSites.Count -gt 0) {
            $Warnings.Add("Could not read the user list of $($SkippedSites.Count) site(s), so guests on them are not listed and a full removal does not touch them: $($SkippedSites -join ', ')")
        }

        # --- Entra guest sweep for the join ---
        $EntraGuests = @()
        if ($StoreUsers.Count -gt 0 -or $SiteGuests.Count -gt 0) {
            try {
                $EntraGuests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,userPrincipalName,mail&`$top=999" -tenantid $TenantFilter -AsApp $true)
            } catch {
                throw "Could not list Entra guest users for cross-referencing: $($_.Exception.Message)"
            }
        }
        $GuestsByUpn = @{}
        $GuestsByMail = @{}
        foreach ($Guest in $EntraGuests) {
            if ($Guest.userPrincipalName) { $GuestsByUpn[$Guest.userPrincipalName.ToLower()] = $Guest }
            if ($Guest.mail) { $GuestsByMail[$Guest.mail.ToLower()] = $Guest }
        }

        # Guests converted to Member, and cross-tenant synced users, keep their #EXT# UPN but are
        # userType Member, so the guest sweep misses them. Graph cannot filter on '#EXT#' inside the
        # UPN, so members are swept once, and only when a guest lookup misses.
        $ExtMemberSweep = @{ Done = $false }

        function Resolve-GuestClassification($LoginName, $AcceptedAs, $InvitedAs) {
            if ("$LoginName" -match '(?i)urn(%3a|:)spo(%3a|:)guest') {
                return @('SharePoint-only (email authenticated)', $null)
            }
            $ClaimsUpn = ("$LoginName" -split '\|')[-1].ToLower()
            foreach ($Pass in 1..2) {
                $EntraUser = $GuestsByUpn[$ClaimsUpn]
                if (-not $EntraUser -and $AcceptedAs) { $EntraUser = $GuestsByMail[([string]$AcceptedAs).ToLower()] }
                if (-not $EntraUser -and $InvitedAs) { $EntraUser = $GuestsByMail[([string]$InvitedAs).ToLower()] }
                if ($EntraUser -or $ExtMemberSweep.Done) { break }
                $ExtMemberSweep.Done = $true
                try {
                    foreach ($Member in New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Member'&`$select=id,userPrincipalName,mail&`$top=999" -tenantid $TenantFilter -AsApp $true) {
                        if ([string]$Member.userPrincipalName -notlike '*#EXT#*') { continue }
                        $GuestsByUpn[$Member.userPrincipalName.ToLower()] = $Member
                        if ($Member.mail) { $GuestsByMail[$Member.mail.ToLower()] = $Member }
                    }
                } catch {
                    $Warnings.Add("Could not list Entra members with external (#EXT#) accounts, so converted or cross-tenant synced guests may show as Orphaned B2B: $($_.Exception.Message)")
                }
            }
            if ($EntraUser) { return @('Entra B2B', $EntraUser) }
            return @('Orphaned B2B (not in Entra)', $null)
        }

        # Soonest site-level expiry across a guest's sites (null when none set), so the
        # list can be sorted by it.
        function Get-NextExpiration($SiteAccess) {
            $Dates = @($SiteAccess | Where-Object { $_.Expiration } | ForEach-Object { [datetime]$_.Expiration })
            if ($Dates.Count -eq 0) { return $null }
            return ($Dates | Sort-Object | Select-Object -First 1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $SeenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($User in $StoreUsers) {
            $GuestType, $EntraUser = Resolve-GuestClassification $User.LoginName $User.AcceptedAs $User.InvitedAs
            # Match this store entry to any site membership sweep hit for a Sites column.
            $MatchKey = $null
            foreach ($Key in $SiteGuests.Keys) {
                $SG = $SiteGuests[$Key]
                if (($User.AcceptedAs -and $SG.Email -eq $User.AcceptedAs) -or ($EntraUser -and $Key -eq $EntraUser.userPrincipalName.ToLower())) { $MatchKey = $Key; break }
            }
            if ($MatchKey) { [void]$SeenKeys.Add($MatchKey) }
            # Direct assignment keeps the List intact; an if-expression would pipeline-unwrap
            # a single-element list to a scalar and the API would emit a string, not an array.
            $RowSites = [System.Collections.Generic.List[string]]::new()
            $RowSiteAccess = [System.Collections.Generic.List[object]]::new()
            if ($MatchKey) {
                $RowSites = $SiteGuests[$MatchKey].Sites
                $RowSiteAccess = $SiteGuests[$MatchKey].SiteAccess
            }
            $Rows.Add([PSCustomObject]@{
                    DisplayName = $User.DisplayName
                    InvitedAs   = $User.InvitedAs
                    AcceptedAs  = $User.AcceptedAs
                    # Store entries often carry no login; the site sweep's claims login fills the gap.
                    LoginName   = if ($User.LoginName) { $User.LoginName } elseif ($MatchKey) { $SiteGuests[$MatchKey].LoginName } else { $null }
                    UniqueId    = $User.UniqueId
                    WhenCreated = ConvertFrom-CsomDate $User.WhenCreated
                    InvitedBy   = $User.InvitedBy
                    GuestType   = $GuestType
                    InEntra     = [bool]$EntraUser
                    EntraUserId = $EntraUser.id
                    Source      = 'External users store'
                    Sites          = $RowSites
                    SiteAccess     = $RowSiteAccess
                    NextExpiration = Get-NextExpiration $RowSiteAccess
                })
        }

        # Guests that only exist as site members (never redeemed / store aged out)
        foreach ($Key in $SiteGuests.Keys) {
            if ($SeenKeys.Contains($Key)) { continue }
            $SG = $SiteGuests[$Key]
            $GuestType, $EntraUser = Resolve-GuestClassification $SG.LoginName $SG.Email $null
            $Rows.Add([PSCustomObject]@{
                    DisplayName = $SG.Title
                    InvitedAs   = $null
                    AcceptedAs  = $SG.Email
                    LoginName   = $SG.LoginName
                    UniqueId    = $null
                    WhenCreated = $null
                    InvitedBy   = $null
                    GuestType   = $GuestType
                    InEntra     = [bool]$EntraUser
                    EntraUserId = $EntraUser.id
                    Source      = 'Site membership'
                    Sites          = $SG.Sites
                    SiteAccess     = $SG.SiteAccess
                    NextExpiration = Get-NextExpiration $SG.SiteAccess
                })
        }

        $Body = @($Rows)
        $StatusCode = if ($Warnings.Count -gt 0) { [HttpStatusCode]::MultiStatus } else { [HttpStatusCode]::OK }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list SharePoint external users: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body; 'Metadata' = @{ 'Warnings' = @($Warnings) } }
        })
}