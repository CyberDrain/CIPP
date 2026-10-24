function Test-CIPPAuditLogRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $Rows,
        # Partition holding these rows in CacheWebhooks. V2 keys the cache per search
        # (tenant|searchId); every row in one call comes from a single search, so one key covers
        # the batch. Defaults to the tenant, leaving older callers unaffected.
        [string]$CachePartitionKey,
        # Remove processed rows with the plain delete instead of the part-aware one, on the
        # caller's guarantee that it sweeps the whole cache partition afterwards.
        # Remove-CIPPAzDataTableEntity also deletes the -partN rows of entities that were split for
        # size, and that guarantee costs ~2.7x per row - measured at 37% of this stage, the single
        # largest slice of it. A V2 caller owns one partition per search, so it can clear anything
        # left behind in one keys-only pass and does not need it paid per record. Off by default:
        # a caller that does not sweep must keep the part-aware delete or it orphans part rows.
        [switch]$CallerSweepsCachePartition,
        # Shape and match only: no cache deletes, claims or alerts. The feed uses it to keep only the records a rule matches.
        [switch]$EvaluateOnly
    )
    if (-not $CachePartitionKey) { $CachePartitionKey = $TenantFilter }

    try {
        # Pre-compiled regex patterns for GUID matching (performance optimization)
        $script:StandardGuidRegex = [regex]'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        $script:ClientIpRegex = [regex]'^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $script:ReservedIpRegex = [regex]::new(
            '^(?:10\.|127\.|0\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|(?:22[4-9]|23[0-9]|24[0-9]|25[0-5])\.|::1?$|fe[89ab]|f[cd]|ff)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        $script:PartnerUpnRegex = [regex]'user_([0-9a-f]{32})@([^@]+\.onmicrosoft\.com)'
        $script:KeyDescriptionRegex = [regex]'\[KeyIdentifier=(?<Id>[^,\]]*),KeyType=(?<Type>[^,\]]*),KeyUsage=(?<Usage>[^,\]]*)'
        $script:GuidMappingMarkers = [string[]]@('user_', 'tenant:')
        $script:PartnerExchangeRegex = [regex]'([^\\]+\.onmicrosoft\.com)\\tenant:\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}),\s*object:\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})'

        # Directory GUIDs are joined in the record loop by PSMembers.MapStringProperties. The values it hands back - those
        # holding a partner UPN or an Exchange partner identity - map to the partner tenant's users here.
        function Add-CIPPPartnerMappings {
            param(
                $DataObject,
                $PartnerMatches,
                $PartnerUserLookup,
                [string]$PropertyPrefix = ''
            )

            $Mapped = $null
            foreach ($Match in $PartnerMatches) {
                $MappedValue = $null
                $Found = $false
                $PropValue = $Match.Value
                if ($PropValue.Contains('user_')) {
                    $PartnerMatch = $script:PartnerUpnRegex.Match($PropValue)
                    if ($PartnerMatch.Success -and $PartnerMatch.Groups[1].Value.Length -eq 32) {
                        $HexId = $PartnerMatch.Groups[1].Value
                        $Guid = "$($HexId.Substring(0,8))-$($HexId.Substring(8,4))-$($HexId.Substring(12,4))-$($HexId.Substring(16,4))-$($HexId.Substring(20,12))"
                        Write-Information "Found partner UPN format: $PropValue with GUID: $Guid and tenant: $($PartnerMatch.Groups[2].Value)"
                        if ($PartnerUserLookup.ContainsKey($Guid)) { $MappedValue = $PartnerUserLookup[$Guid].userPrincipalName; $Found = $true }
                    }
                }
                if (-not $Found -and $PropValue.Contains('tenant:')) {
                    $PartnerMatch = $script:PartnerExchangeRegex.Match($PropValue)
                    if ($PartnerMatch.Success) {
                        $ObjectGuid = $PartnerMatch.Groups[3].Value
                        Write-Information "Found partner exchange format: customer tenant $($PartnerMatch.Groups[1].Value), partner tenant $($PartnerMatch.Groups[2].Value), object $ObjectGuid"
                        if ($PartnerUserLookup.ContainsKey($ObjectGuid)) { $MappedValue = $PartnerUserLookup[$ObjectGuid].userPrincipalName; $Found = $true }
                    }
                }
                if (-not $Found) { continue }
                ($Mapped ??= [ordered]@{})["$PropertyPrefix$($Match.Name)"] = $MappedValue
            }
            # Mapped values replace any existing property and are appended, as Add-Member -Force did.
            if ($Mapped) { [CIPP.PSMembers]::AddNoteProperties($DataObject, $Mapped, $true) }
        }

        #$FunctionStartTime = Get-Date

        $Results = [PSCustomObject]@{
            TotalLogs     = 0
            MatchedLogs   = 0
            MatchedRules  = @()
            DataToProcess = @()
            Error         = $null
        }

        # Get the CacheWebhooks table for removing processed rows
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'

        $ExtendedPropertiesIgnoreList = @(
            'SAS:EndAuth'
            'SAS:ProcessAuth'
            'deviceAuth:ReprocessTls'
            'Consent:Set'
        )

        # Properties the record loop assigns to later. They have to exist first: assigning to an
        # absent property on a PSCustomObject throws. Built once and read by Add-Member per record.
        # HasLocationData is in here too, so emitting the record is a plain assignment rather than a
        # second Select-Object projection over the whole property bag.
        $RecordPlaceholders = @{
            CIPPAction             = $null
            CIPPBecActions         = $null
            CIPPClause             = $null
            CIPPGeoLocation        = $null
            CIPPBadRepIP           = $null
            CIPPHostedIP           = $null
            CIPPIPDetected         = $null
            CIPPLocationInfo       = $null
            CIPPExtendedProperties = $null
            CIPPDeviceProperties   = $null
            CIPPParameters         = $null
            CIPPModifiedProperties = $null
            AuditRecord            = $null
            HasLocationData        = $null
        }

        $Configuration = @(Get-CIPPAuditLogRuleSet -TenantFilter $TenantFilter)
        $PendingDeletes = [System.Collections.Generic.List[object]]::new()
        # The actor/target fields cost a pass over two arrays per record, so they are only derived when a rule names one.
        $DeriveActorTarget = @($Configuration.Conditions).Where({ $_ -match 'CIPP(ActorIsTarget|ActorType|TargetType)' }, 'First').Count -gt 0
        $JoinActor = @($Configuration.Conditions).Where({ $_ -match '"label"\s*:\s*"CIPPActor"' }, 'First').Count -gt 0

        # Only the referenced entries of a cached blob, as the same hashtable a full ConvertFrom-Json -AsHashtable gives.
        # One pass over the blob picks the entries; a blob that is not a valid JSON object takes the full parse instead.
        function Get-CIPPLookupSubset {
            param([string]$Json, $Ids)
            if (-not $Json) { return @{} }
            try {
                $Selected = [CIPP.CippJson]::SelectMembers($Json, $Ids)
                if ($null -ne $Selected) { return (ConvertFrom-Json -InputObject $Selected -AsHashtable -ErrorAction Stop) ?? @{} }
            } catch { Write-Information 'Directory subset did not parse; loading the whole blob' }
            ($Json | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
        }

        $Table = Get-CIPPTable -tablename 'cacheauditloglookups'
        $1dayago = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        # A later slice of the same search reuses the directory a large slice parsed (see Push-AuditLogTenantProcessV2).
        $SearchLookups = $script:AuditRuleSearchLookups
        if ($SearchLookups.Tenant -ne $TenantFilter) { $SearchLookups = $null }
        $LookupsReused = $null -ne $SearchLookups.UserLookup
        # GUID mapping only adds CIPP-prefixed names, so an evaluation whose rules name none never needs the directory. The
        # actor, key and geo fields are CIPP-prefixed too but come from the record and the geo lookup.
        if ($EvaluateOnly -and -not @($Configuration.Conditions).Where({ $_ -match '"label"\s*:\s*"CIPP(?!(Actor|ActorIsTarget|ActorType|TargetType|AddedKeyTypes|AddedKeys|GeoLocation|BadRepIP|HostedIP|IPDetected)")' }, 'First').Count) {
            $UserLookup = @{}
            $GroupLookup = @{}
            $DeviceLookup = @{}
            $ServicePrincipalLookup = @{}
            $Lookups = $null
            $LookupsReused = $true
        } elseif ($LookupsReused) {
            $UserLookup = $SearchLookups.UserLookup
            $GroupLookup = $SearchLookups.GroupLookup
            $DeviceLookup = $SearchLookups.DeviceLookup
            $ServicePrincipalLookup = $SearchLookups.ServicePrincipalLookup
            $Lookups = $null
        } else {
            $Lookups = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter' and Timestamp gt datetime'$1dayago'"
        }

        # Check if cached data needs refresh (wrong format or corrupted)
        $NeedsRefresh = $false
        $LookupFailed = $false
        if ($Lookups) {
            try {
                # Test-Json validates without building the objects.
                $TestUser = ($Lookups | Where-Object { $_.RowKey -eq 'users' }).Data
                if ($TestUser) {
                    $Trimmed = $TestUser.Trim()
                    if ($Trimmed -eq 'null' -or $Trimmed -eq '[]') {
                        Write-Warning 'Cached data is null after parsing, triggering refresh'
                        $NeedsRefresh = $true
                    } elseif (-not (Test-Json -Json $TestUser -ErrorAction SilentlyContinue)) {
                        throw 'Cached directory data is not valid JSON'
                    }
                } else {
                    Write-Warning 'Cached data is empty, triggering refresh'
                    $NeedsRefresh = $true
                }
            } catch {
                Write-Warning "Error parsing cached data: $($_.Exception.Message), triggering refresh"
                $NeedsRefresh = $true
            }
        }

        if ($LookupsReused) {
            Write-Information "Reusing this search's directory lookups for tenant $TenantFilter"
        } elseif (!$Lookups -or $NeedsRefresh) {
            # Try CippReportingDB first (pre-populated by timer, same pattern as Add-CIPPApplicationPermission).
            # Get-CIPPTestData rather than New-CIPPDbRequest: the shared in-process cache lets
            # concurrent batches reuse one copy of the directory data, and -Fields parses only
            # what the mapping reads - unprojected per-batch loads OOM'd the container on
            # large tenants.
            Write-Information "Checking CippReportingDB for directory data for tenant $TenantFilter"
            try {
                $Users = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'displayName', 'userPrincipalName', 'accountEnabled')
                $Groups = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Groups' -Fields 'id', 'displayName', 'mailEnabled', 'securityEnabled')
                $Devices = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'Devices' -Fields 'id', 'displayName', 'deviceId')
                $ServicePrincipals = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Fields 'id', 'appId', 'displayName', 'appDisplayName', 'accountEnabled', 'servicePrincipalType', 'tags')
                Write-Information "Loaded from CippReportingDB: $($Users.Count) users, $($Groups.Count) groups, $($Devices.Count) devices, $($ServicePrincipals.Count) service principals"
            } catch {
                Write-Information "CippReportingDB query failed for ${TenantFilter}: $($_.Exception.Message)"
                $Users = @()
                $Groups = @()
                $Devices = @()
                $ServicePrincipals = @()
            }

            if (!$Users -or !$ServicePrincipals) {
                # DB cache is empty or unavailable, fall back to Graph bulk request
                Write-Information "CippReportingDB has no data for $TenantFilter, falling back to Graph bulk request"
                $Requests = @(
                    @{
                        id     = 'users'
                        url    = '/users?$select=id,displayName,userPrincipalName,accountEnabled&$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'groups'
                        url    = '/groups?$select=id,displayName,mailEnabled,securityEnabled&$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'devices'
                        url    = '/devices?$select=id,displayName,deviceId&$top=999'
                        method = 'GET'
                    }
                    @{
                        id     = 'servicePrincipals'
                        url    = '/servicePrincipals?$select=id,displayName&$top=999'
                        method = 'GET'
                    }
                )
                try {
                    $Response = New-GraphBulkRequest -TenantId $TenantFilter -Requests $Requests
                } catch {
                    # Rules still run on the raw records; only GUID-to-name enrichment is lost.
                    Write-Warning "Directory lookup failed for $TenantFilter, processing audit logs without name enrichment: $($_.Exception.Message)"
                    $Response = $null
                    $LookupFailed = $true
                }
                $Users = ($Response | Where-Object { $_.id -eq 'users' }).body.value ?? @()
                $Groups = ($Response | Where-Object { $_.id -eq 'groups' }).body.value ?? @()
                $Devices = ($Response | Where-Object { $_.id -eq 'devices' }).body.value ?? @()
                $ServicePrincipals = @(($Response | Where-Object { $_.id -eq 'servicePrincipals' }).body.value) | Select-Object id, displayName
                $Response = $null
            }

            # Build hashtables for O(1) GUID lookups
            Write-Information "Building hashtable lookups for tenant $TenantFilter"
            $UserLookup = @{}
            foreach ($User in $Users) {
                if (![string]::IsNullOrEmpty($User.id)) {
                    $UserLookup[$User.id] = $User
                }
            }

            $GroupLookup = @{}
            foreach ($Group in $Groups) {
                if (![string]::IsNullOrEmpty($Group.id)) {
                    $GroupLookup[$Group.id] = $Group
                }
            }

            $DeviceLookup = @{}
            foreach ($Device in $Devices) {
                if (![string]::IsNullOrEmpty($Device.id)) {
                    $DeviceLookup[$Device.id] = $Device
                }
            }

            $ServicePrincipalLookup = @{}
            foreach ($SP in $ServicePrincipals) {
                if (![string]::IsNullOrEmpty($SP.id)) {
                    $ServicePrincipalLookup[$SP.id] = $SP
                }
                # Also index by appId for dual lookup capability
                if (![string]::IsNullOrEmpty($SP.appId)) {
                    $ServicePrincipalLookup[$SP.appId] = $SP
                }
            }
            Write-Information "Built hashtables: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"

            # Cache the hashtable lookups for 1 day (storing as JSON)
            $Entities = @(
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'users'
                    Data         = [string]($UserLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'groups'
                    Data         = [string]($GroupLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'devices'
                    Data         = [string]($DeviceLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
                @{
                    PartitionKey = $TenantFilter
                    RowKey       = 'servicePrincipals'
                    Data         = [string]($ServicePrincipalLookup | ConvertTo-Json -Compress)
                    Format       = 'hashtable'
                }
            )
            # Save the cached lookups, unless they are empty because the lookup failed
            if (-not $LookupFailed) {
                Add-CIPPAzDataTableEntity @Table -Entity $Entities -Force
                Write-Information "Cached directory hashtable lookups for tenant $TenantFilter"
            }
        } else {
            # Use cached lookups - check if they're already hashtables or need conversion
            $UsersLookup = $Lookups | Where-Object { $_.RowKey -eq 'users' }
            $GroupsLookup = $Lookups | Where-Object { $_.RowKey -eq 'groups' }
            $DevicesLookup = $Lookups | Where-Object { $_.RowKey -eq 'devices' }
            $ServicePrincipalsLookup = $Lookups | Where-Object { $_.RowKey -eq 'servicePrincipals' }

            # Check if cached data is already in hashtable format
            $IsHashtableFormat = $UsersLookup.Format -eq 'hashtable'

            if ($IsHashtableFormat) {
                # Most batches hold a handful of records, so only the directory entries they reference are loaded.
                # Each record adds ~5 distinct GUIDs; past ~50 records the full parse is cheaper.
                if (@($Rows).Count -le 50) {
                    Write-Information "Loading referenced directory entries from cache for tenant $TenantFilter"
                    $IdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    foreach ($Row in $Rows) {
                        if ($null -eq $Row) { continue }
                        [CIPP.PSMembers]::CollectStringValues($Row, $script:StandardGuidRegex, $IdSet)
                        if ($null -ne $Row.auditData) { [CIPP.PSMembers]::CollectStringValues($Row.auditData, $script:StandardGuidRegex, $IdSet) }
                    }
                    $UserLookup = Get-CIPPLookupSubset -Json $UsersLookup.Data -Ids $IdSet
                    $GroupLookup = Get-CIPPLookupSubset -Json $GroupsLookup.Data -Ids $IdSet
                    $DeviceLookup = Get-CIPPLookupSubset -Json $DevicesLookup.Data -Ids $IdSet
                    $RawSPLookup = Get-CIPPLookupSubset -Json $ServicePrincipalsLookup.Data -Ids $IdSet
                } else {
                    Write-Information "Loading pre-built hashtable lookups from cache for tenant $TenantFilter"
                    $UserLookup = ($UsersLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                    $GroupLookup = ($GroupsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                    $DeviceLookup = ($DevicesLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                    $RawSPLookup = ($ServicePrincipalsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
                }
                $ServicePrincipalLookup = @{}
                foreach ($key in $RawSPLookup.Keys) {
                    $sp = $RawSPLookup[$key]
                    $ServicePrincipalLookup[$key] = [ordered]@{
                        id                   = $sp.id
                        appId                = $sp.appId
                        displayName          = $sp.displayName
                        appDisplayName       = $sp.appDisplayName
                        accountEnabled       = $sp.accountEnabled
                        servicePrincipalType = $sp.servicePrincipalType
                        tags                 = $sp.tags
                    }
                }
                Write-Information "Loaded hashtables: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"
                if ($SearchLookups -and @($Rows).Count -gt 50) {
                    $SearchLookups.UserLookup = $UserLookup
                    $SearchLookups.GroupLookup = $GroupLookup
                    $SearchLookups.DeviceLookup = $DeviceLookup
                    $SearchLookups.ServicePrincipalLookup = $ServicePrincipalLookup
                }
            } else {
                # Old format (array) - convert to hashtables
                Write-Information "Converting legacy array cache to hashtables for tenant $TenantFilter"
                $Users = @(($UsersLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, displayName, userPrincipalName, accountEnabled
                $Groups = @(($GroupsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, displayName, mailEnabled, securityEnabled
                $Devices = @(($DevicesLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, displayName, deviceId
                $ServicePrincipals = @(($ServicePrincipalsLookup.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)) | Select-Object id, appId, displayName, appDisplayName, accountEnabled, servicePrincipalType, tags

                # Build hashtables
                $UserLookup = @{}
                foreach ($User in $Users) {
                    if (![string]::IsNullOrEmpty($User.id)) {
                        $UserLookup[$User.id] = $User
                    }
                }

                $GroupLookup = @{}
                foreach ($Group in $Groups) {
                    if (![string]::IsNullOrEmpty($Group.id)) {
                        $GroupLookup[$Group.id] = $Group
                    }
                }

                $DeviceLookup = @{}
                foreach ($Device in $Devices) {
                    if (![string]::IsNullOrEmpty($Device.id)) {
                        $DeviceLookup[$Device.id] = $Device
                    }
                }

                $ServicePrincipalLookup = @{}
                foreach ($SP in $ServicePrincipals) {
                    if (![string]::IsNullOrEmpty($SP.id)) {
                        $ServicePrincipalLookup[$SP.id] = $SP
                    }
                    if (![string]::IsNullOrEmpty($SP.appId)) {
                        $ServicePrincipalLookup[$SP.appId] = $SP
                    }
                }
                Write-Information "Built hashtables from legacy cache: $($UserLookup.Count) users, $($GroupLookup.Count) groups, $($DeviceLookup.Count) devices, $($ServicePrincipalLookup.Count) service principals"
            }
        }

        # Partner users: the shared lookup (memoised per worker, cached for a day) the BEC run reads too.
        $PartnerUserLookup = Get-CIPPPartnerUserLookup

        try {
            $LogCount = $Rows.count
            $RunGuid = (New-Guid).Guid
            Write-Warning "Logs to process: $LogCount - RunGuid: $($RunGuid) - $($TenantFilter)"
            $Results.TotalLogs = $LogCount
            Write-Information "RunGuid: $RunGuid - Collecting logs"
            $SearchResults = $Rows
        } catch {
            Write-Warning "Error getting audit logs: $($_.Exception.Message)"
            Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit logs' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
            throw $_
        }

        # Exclusions and trusted IPs join the same per-tenant memo as the rule set and the directory
        # lookups. Both were read on every invocation - once per 500-record slice, per tenant - for
        # data that changes when an operator edits a list, not between slices of one batch.
        $AuditLogUserExclusions = Get-CIPPTable -TableName 'AuditLogUserExclusions'
        if ($null -eq $script:AuditRuleListCache) { $script:AuditRuleListCache = @{} }
        $ListNow = [datetime]::UtcNow
        $ListEntry = $script:AuditRuleListCache[$TenantFilter]
        if ($ListEntry -and $ListEntry.Expires -gt $ListNow) {
            $ExcludedUsers = $ListEntry.ExcludedUsers
            $IPListEntries = $ListEntry.IPListEntries
        } else {
            foreach ($CachedTenant in @($script:AuditRuleListCache.Keys)) {
                if ($script:AuditRuleListCache[$CachedTenant].Expires -le $ListNow) {
                    $script:AuditRuleListCache.Remove($CachedTenant)
                }
            }
            $ExcludedUsers = Get-CIPPAzDataTableEntity @AuditLogUserExclusions -Filter "PartitionKey eq '$TenantFilter'"
            # Trusted and Blocked entries, single addresses and CIDR ranges alike. Blocked ones matter
            # here only because the most specific range wins: a blocked address inside a trusted
            # range must stay untrusted.
            $IPListEntries = @(Get-CIPPIPAllowBlockList -TenantFilter $TenantFilter)
            $script:AuditRuleListCache[$TenantFilter] = [PSCustomObject]@{
                Expires       = $ListNow.AddMinutes(2)
                ExcludedUsers = $ExcludedUsers
                IPListEntries = $IPListEntries
            }
        }

        if ($LogCount -gt 0) {

            # Each distinct client IP is normalised and classified once per batch, here - Trusted (by the list),
            # Reserved, or Geo - and the record loop below reads the answer from $NormalizedIPs and $IPClass.
            $IPClass = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
            $GeoPrefetchIPs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $NormalizedIPs = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
            foreach ($AuditRecord in $SearchResults) {
                $RawIp = [string]($AuditRecord.auditData ?? $AuditRecord).clientip
                if (-not $RawIp -or $null -ne $NormalizedIPs[$RawIp] -or $RawIp -match '[X]+') { continue }
                $cip = $script:ClientIpRegex.Replace($RawIp, '$1') -replace '[\[\]]', ''
                $NormalizedIPs[$RawIp] = $cip
                if ($null -ne $IPClass[$cip]) { continue }
                if ($IPListEntries.Count -gt 0 -and (Resolve-CIPPIPAllowBlockList -IPAddress $cip -Entries $IPListEntries).State -eq 'Trusted') {
                    $IPClass[$cip] = 'Trusted'
                } elseif ($script:ReservedIpRegex.IsMatch($cip)) {
                    $IPClass[$cip] = 'Reserved'
                } else {
                    $IPClass[$cip] = 'Geo'
                    $null = $GeoPrefetchIPs.Add($cip)
                }
            }
            $GeoLookup = @{}
            if ($GeoPrefetchIPs.Count -gt 0) {
                try {
                    $GeoLookup = Get-CIPPGeoIPLocationBatch -IPs @($GeoPrefetchIPs)
                    Write-Information "Geo prefetch: $($GeoLookup.Count)/$($GeoPrefetchIPs.Count) distinct IPs resolved"
                } catch {
                    #Write-Warning "Geo prefetch failed, falling back to per-record lookup: $($_.Exception.Message)"
                }
            }

            # A record's cache row is deleted only once its alert has gone out (after dispatch, below), so a crash
            # mid-dispatch leaves the row for the retry. 100 is the table service's per-transaction maximum.
            $DeleteFlushSize = 100
            # Member changes go through PSMembers, one call each: from PowerShell every Properties.Add or Remove costs ~25 us.
            $DroppedProperties = [string[]]@('ExtendedProperties', 'DeviceProperties', 'parameters')
            # GUID mapping: a user maps to its UPN; a group, device or service principal to its whole directory entry.
            $GuidLookups = [System.Collections.IDictionary[]]@($UserLookup, $GroupLookup, $DeviceLookup, $ServicePrincipalLookup)
            $GuidLookupFields = [string[]]@('userPrincipalName', '', '', '')

            $ProcessedData = foreach ($AuditRecord in $SearchResults) {
                $RootProperties = $AuditRecord
                # A copy plus one batch of placeholders, not a Select-Object projection, which re-derives the whole
                # property set per record. No overwrite, which matches what
                # `Select-Object *, Dup -ErrorAction SilentlyContinue` did - a record already
                # carrying one of these names keeps its own value rather than being nulled.
                #
                # ExtendedProperties / DeviceProperties / parameters are dropped here rather than
                # excluded from the emitted object at the bottom of the loop. They are flattened
                # onto CIPP* copies below, which now read them from the source record, so carrying
                # them through only to strip them again was pure copying - and dropping them here
                # also shortens both GUID-mapping passes over this object.
                #
                # Guarded, because a record with no auditData must still land in the per-record
                # catch below the way it did before, not throw out of the whole batch.
                # Graph search records wrap the audit record in auditData; feed records are the audit record.
                $Wrapped = $AuditRecord.auditData
                $Source = $Wrapped ?? $AuditRecord
                $Data = $null
                if ($null -ne $Source) {
                    $Data = [CIPP.PSMembers]::CopyExcept($Source, $DroppedProperties)
                }
                try {
                    # Attempt to locate GUIDs in $Data and match them with their corresponding user, group, device, or service principal using O(1) hashtable lookups
                    # Write-Information 'Checking Data for GUIDs to map to users, groups, devices, or service principals'
                    $PartnerMatches = [CIPP.PSMembers]::MapStringProperties($Data, $GuidLookups, $GuidLookupFields, 'CIPP', $script:GuidMappingMarkers)
                    if ($PartnerMatches.Count -gt 0) { Add-CIPPPartnerMappings -DataObject $Data -PartnerMatches $PartnerMatches -PartnerUserLookup $PartnerUserLookup -PropertyPrefix 'CIPP' }
                    # Placeholders go on after the mapping, so it walks 14 fewer properties per record.
                    [CIPP.PSMembers]::AddNoteProperties($Data, $RecordPlaceholders, $false)

                    # Also check root properties for GUIDs and partner UPNs
                    # Write-Information 'Checking RootProperties for GUIDs to map to users, groups, devices, or service principals'
                    # A feed record is its own root, already mapped onto $Data above.
                    if ($null -ne $Wrapped) {
                        $PartnerMatches = [CIPP.PSMembers]::MapStringProperties($RootProperties, $GuidLookups, $GuidLookupFields, '', $script:GuidMappingMarkers)
                        if ($PartnerMatches.Count -gt 0) { Add-CIPPPartnerMappings -DataObject $RootProperties -PartnerMatches $PartnerMatches -PartnerUserLookup $PartnerUserLookup }
                    }

                    # Flattened onto $Data so rules can match the property names directly. One
                    # Add-Member per sub-object: per-property calls rebuild the property bag each time.
                    # One accumulated hash table and a single Add-Member, rather than one per
                    # sub-object. Each Add-Member extends the property bag, and four per record
                    # measured at 198 us / 132 KB against 125 us / 87 KB for one. Collision
                    # behaviour is unchanged: later sub-objects overwrote earlier keys through
                    # -Force before, and overwrite the same keys in the hash table now.
                    # ConvertTo-Json takes -InputObject rather than a pipeline, which skips setting
                    # up a pipeline per call for no change in output.
                    # The first three read from $Source, not $Data - they are deliberately no longer
                    # copied onto $Data. ModifiedProperties stays on $Data and is read from there.
                    $Flattened = @{}
                    # Each sub-object is read once: every member read off a record is a dynamic lookup.
                    $SubObject = $Source.ExtendedProperties
                    if ($SubObject) {
                        $Data.CIPPExtendedProperties = ([CIPP.CippJson]::ToJson($SubObject, 10) ?? (ConvertTo-Json -InputObject $SubObject -Compress -Depth 10))
                        foreach ($Prop in $SubObject) {
                            # Must be a real loop: `continue` inside ForEach-Object unwinds to the
                            # enclosing foreach and drops the whole record.
                            if ($Prop.Value -in $ExtendedPropertiesIgnoreList) { continue }
                            if (-not [string]$Prop.Name) { continue }
                            $Flattened[$Prop.Name] = $Prop.Value
                        }
                    }
                    $SubObject = $Source.DeviceProperties
                    if ($SubObject) {
                        $Data.CIPPDeviceProperties = ([CIPP.CippJson]::ToJson($SubObject, 10) ?? (ConvertTo-Json -InputObject $SubObject -Compress -Depth 10))
                        foreach ($Prop in $SubObject) {
                            if (-not [string]$Prop.Name) { continue }
                            $Flattened[$Prop.Name] = $Prop.Value
                        }
                    }
                    $SubObject = $Source.parameters
                    if ($SubObject) {
                        $Data.CIPPParameters = ([CIPP.CippJson]::ToJson($SubObject, 10) ?? (ConvertTo-Json -InputObject $SubObject -Compress -Depth 10))
                        foreach ($Prop in $SubObject) {
                            if (-not [string]$Prop.Name) { continue }
                            $Flattened[$Prop.Name] = $Prop.Value
                        }
                    }
                    $SubObject = $Data.ModifiedProperties
                    if ($SubObject) {
                        $Data.CIPPModifiedProperties = ([CIPP.CippJson]::ToJson($SubObject, 10) ?? (ConvertTo-Json -InputObject $SubObject -Compress -Depth 10))
                        try {
                            foreach ($Prop in $SubObject) {
                                if (-not [string]$Prop.Name) { continue }
                                $Flattened["$($Prop.Name)"] = "$($Prop.NewValue)"
                                $Flattened["Previous_Value_$($Prop.Name)"] = "$($Prop.OldValue)"
                                if ($Prop.Name -eq 'KeyDescription') {
                                    # Keys in the new list but not the old; only Verify keys can sign in as the app.
                                    $OldKeyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                                    foreach ($KeyMatch in $script:KeyDescriptionRegex.Matches([string]$Prop.OldValue)) {
                                        [void]$OldKeyIds.Add($KeyMatch.Groups['Id'].Value)
                                    }
                                    $AddedKeyTypes = [System.Collections.Generic.List[string]]::new()
                                    $AddedKeys = [System.Collections.Generic.List[string]]::new()
                                    foreach ($KeyMatch in $script:KeyDescriptionRegex.Matches([string]$Prop.NewValue)) {
                                        if ($KeyMatch.Groups['Usage'].Value -ne 'Verify' -or $OldKeyIds.Contains($KeyMatch.Groups['Id'].Value)) { continue }
                                        $KeyType = $KeyMatch.Groups['Type'].Value
                                        $AddedKeys.Add("$($KeyType): $($KeyMatch.Groups['Id'].Value)")
                                        if (-not $AddedKeyTypes.Contains($KeyType)) { $AddedKeyTypes.Add($KeyType) }
                                    }
                                    $Flattened['CIPPAddedKeyTypes'] = $AddedKeyTypes -join ','
                                    $Flattened['CIPPAddedKeys'] = $AddedKeys -join ', '
                                }
                            }
                        } catch {
                            Write-Information "Error flattening ModifiedProperties for $($AuditRecord.id): $($_.Exception.Message)"
                        }
                    }
                    if ($JoinActor -and $Data.Actor) {
                        # One string so a rule can test who acted (e.g. MS-PIM); -notlike against the Actor array itself is always true.
                        $Flattened['CIPPActor'] = @(foreach ($ActorEntry in $Data.Actor) { [string]$ActorEntry.ID }) -join ', '
                    }
                    if ($Flattened.Count -gt 0) {
                        [CIPP.PSMembers]::AddNoteProperties($Data, $Flattened, $true)
                    }


                    if ($DeriveActorTarget) {
                        # Identity entries only (object ids, ServicePrincipal_/User_/Application_ ids, UPNs), never the
                        # type words or the tenant id, which every actor and target of a tenant share.
                        $Ignore = @('User', 'ServicePrincipal', 'Application', 'Group', 'Device', 'NotAgentic', 'Agentic', 'Other', [string]$Source.ActorContextId, [string]$Source.TargetContextId)
                        $ActorIds = @(foreach ($Entry in @($Source.Actor)) { if ($Entry.Type -in 2, 4, 5 -and $Entry.ID -and $Entry.ID -notin $Ignore) { [string]$Entry.ID } })
                        $TargetIds = @(foreach ($Entry in @($Source.Target)) { if ($Entry.Type -in 2, 4, 5 -and $Entry.ID -and $Entry.ID -notin $Ignore) { [string]$Entry.ID } })
                        # Strings, not booleans: a rule's 'False' would compare equal to $true.
                        [CIPP.PSMembers]::AddNoteProperties($Data, [ordered]@{
                                CIPPActorIsTarget = [string]($ActorIds.Where({ $_ -in $TargetIds }, 'First').Count -gt 0)
                                CIPPActorType     = [string]$(foreach ($Id in $ActorIds) { if ($Id -match '^(ServicePrincipal|User|Application)_') { $Matches[1]; break } })
                                CIPPTargetType    = [string]$(foreach ($Id in $TargetIds) { if ($Id -match '^(ServicePrincipal|User|Application)_') { $Matches[1]; break } })
                            }, $true)
                    }

                    $HasLocationData = $false
                    # Redacted addresses ('XXX') are ignored. The prefetch pass normalised the record's own address; one a
                    # flattened property replaced is normalised here.
                    $RawIp = [string]$Data.clientip
                    $ClientIp = $NormalizedIPs[$RawIp]
                    if ($null -eq $ClientIp -and $RawIp -and $RawIp -notmatch '[X]+') { $ClientIp = $script:ClientIpRegex.Replace($RawIp, '$1') -replace '[\[\]]', '' }
                    if ($null -ne $ClientIp) {
                        $Data.clientip = $ClientIp
                        # An address the prefetch never saw (one a flattened property supplied) is not trusted, as before.
                        $Class = $IPClass[$ClientIp] ?? $(if ($script:ReservedIpRegex.IsMatch($ClientIp)) { 'Reserved' } else { 'Geo' })
                        if ($Class -ne 'Trusted') {
                            if ($Class -eq 'Reserved') {
                                # A private or loopback address (e.g. ::1 on server-side Exchange cmdlets) has no location,
                                # so location rules skip it rather than treat it as outside every allowed country.
                                $Data.CIPPGeoLocation = 'Reserved'
                                $Data.CIPPBadRepIP = 'Reserved'
                                $Data.CIPPHostedIP = 'Reserved'
                                $Data.CIPPIPDetected = $ClientIp
                                $Data.CIPPLocationInfo = $null
                                $HasLocationData = $false
                            } else {
                                $Loc = $GeoLookup[$ClientIp]
                                if ($Loc) {
                                    $Data.CIPPGeoLocation = $Loc.CountryOrRegion
                                    $Data.CIPPBadRepIP = $Loc.Proxy
                                    $Data.CIPPHostedIP = $Loc.Hosting
                                    $Data.CIPPIPDetected = $ClientIp
                                    $Data.CIPPLocationInfo = ([CIPP.CippJson]::ToJson($Loc, 10) ?? (ConvertTo-Json -InputObject $Loc -Compress -Depth 10))
                                    $HasLocationData = $true
                                } else {
                                    $Data.CIPPGeoLocation = 'Unknown'
                                    $Data.CIPPBadRepIP = 'Unknown'
                                    $Data.CIPPHostedIP = 'Unknown'
                                    $Data.CIPPIPDetected = $ClientIp
                                    $Data.CIPPLocationInfo = $null
                                    $HasLocationData = $false
                                }
                            }
                        }
                    }
                    # Serialised only once the record matches a rule (below), for the Saved Logs raw view.
                    $Data.AuditRecord = $RootProperties
                    # Two plain assignments and emit. This step used to be a second Select-Object
                    # over the whole property bag - a calculated property for HasLocationData plus
                    # -ExcludeProperty for three properties that are no longer copied onto $Data in
                    # the first place. Measured at 77 us / 54 KB for the projection against
                    # 16 us / 14 KB here.
                    $Data.HasLocationData = $HasLocationData
                    $Data
                } catch {
                    #write-warning "Audit log: Error processing data: $($_.Exception.Message)`r`n$($_.InvocationInfo.PositionMessage)"
                    Write-LogMessage -API 'Webhooks' -message 'Error Processing Audit Log Data' -LogData (Get-CippException -Exception $_) -sev Error -tenant $TenantFilter
                }

                if (-not $EvaluateOnly) {
                    $PendingDeletes.Add([PSCustomObject]@{
                            PartitionKey = $CachePartitionKey
                            RowKey       = [string]$AuditRecord.id
                        })
                }
                # No per-record timing warning here. It cost two Get-Date calls, a string
                # interpolation and a warning-stream write for every record - and at production
                # volumes it emits one log line per audit record, which is noise that has to be
                # paid for and then stored. Per-stage timings come from the benchmark harness.
            }

            #write-warning "Processed Data: $(($ProcessedData | Measure-Object).Count) - This should be higher than 0 in many cases, because the where object has not run yet."
            #write-warning "Creating filters - $(($ProcessedData.operation | Sort-Object -Unique) -join ',') - $($TenantFilter)"

            # The rules compile once per rule set and exclusion list instead of on every call: with dozens of rules the
            # parsing, sanitising and script block creation cost far more than matching the few records a feed blob holds.
            if ($null -eq $script:AuditRuleClauseCache) { $script:AuditRuleClauseCache = @{} }
            $ListEntry = $script:AuditRuleListCache[$TenantFilter]
            $Compiled = $script:AuditRuleClauseCache[$TenantFilter]
            if ($null -eq $script:AuditRuleSetCache -or -not $Compiled -or -not [object]::ReferenceEquals($Compiled.RuleSet, $script:AuditRuleSetCache) -or -not [object]::ReferenceEquals($Compiled.Lists, $ListEntry)) {
                $UnsafeValueRegex = [regex]'[;|`\$\{\}]'
                $LocationExcludedUserKeys = @(@($ExcludedUsers | Where-Object { $_.Type -eq 'Location' }).RowKey)
                $Clauses = foreach ($Config in $Configuration) {
                    if ($TenantFilter -in $Config.Excluded.value) {
                        continue
                    }
                    $CIPPClause = [System.Collections.Generic.List[string]]::new()
                    try {
                        $conditions = $Config.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
                        # Build sanitized condition strings instead of direct evaluation
                        $conditionStrings = [System.Collections.Generic.List[string]]::new()
                        $validClause = $true
                        foreach ($condition in $conditions) {
                            $CIPPClause.Add("$($condition.Property.label) is $($condition.Operator.label) $($condition.Input.value)")
                            # Add geo-location prerequisites before the condition itself
                            if ($condition.Property.label -eq 'CIPPGeoLocation') {
                                $conditionStrings.Add('$_.HasLocationData -eq $true')
                                if ($LocationExcludedUserKeys.Count -gt 0) {
                                    $sanitizedKeys = foreach ($key in $LocationExcludedUserKeys) {
                                        $keyStr = [string]$key
                                        if ($UnsafeValueRegex.IsMatch($keyStr)) {
                                            Write-Warning "Blocked unsafe excluded user key: '$keyStr'"
                                            $validClause = $false
                                            break
                                        }
                                        "'{0}'" -f ($keyStr -replace "'", "''")
                                    }
                                    if (-not $validClause) { break }
                                    $conditionStrings.Add("`$_.CIPPUserKey -notin @($($sanitizedKeys -join ', '))")
                                }
                            }
                            $sanitized = Test-CIPPConditionFilter -Condition $condition
                            if ($null -eq $sanitized) {
                                Write-Warning "Skipping rule due to invalid condition for property '$($condition.Property.label)'"
                                $validClause = $false
                                break
                            }
                            $conditionStrings.Add($sanitized)
                        }
                        if (-not $validClause -or $conditionStrings.Count -eq 0) {
                            continue
                        }
                        # A rule without an anchor would be tested on every record; Start-AuditLogFeedV3 warns about it.
                        $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions $conditions
                        if ($null -eq $Anchor) { continue }
                        [PSCustomObject]@{
                            WhereBlock         = [ScriptBlock]::Create($conditionStrings -join ' -and ')
                            Anchor             = $Anchor
                            expectedAction     = $Config.Actions
                            expectedBecActions = $Config.BecActions
                            CIPPClause         = $CIPPClause -join ' and '
                            AlertComment       = $Config.AlertComment
                            CustomSubject      = $Config.CustomSubject
                            PsaTicketPriority  = $Config.PsaTicketPriority
                        }
                    } catch {
                        Write-Warning "Error processing conditions: $($CIPPClause -join ' and '): $($_.Exception.Message)"
                    }
                }
                # ByOperation: Operation -> the clauses whose anchor allows it, in rule order, filled as records arrive.
                $Compiled = [PSCustomObject]@{
                    RuleSet     = $script:AuditRuleSetCache
                    Lists       = $ListEntry
                    Clauses     = @($Clauses)
                    ByOperation = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
                }
                $script:AuditRuleClauseCache[$TenantFilter] = $Compiled
            }

            $MatchedRules = [System.Collections.Generic.List[string]]::new()
            # Each record goes through only the rules its Operation can satisfy, in rule order, and the first rule it
            # matches is the one it alerts on.
            $DataToProcess = foreach ($item in $ProcessedData) {
                $Operation = [string]$item.Operation
                $Candidates = $null
                if (-not $Compiled.ByOperation.TryGetValue($Operation, [ref]$Candidates)) {
                    $Candidates = @(foreach ($clause in $Compiled.Clauses) {
                            if ($clause.Anchor.Literals.Contains($Operation) -or $clause.Anchor.Patterns.Where({ $_.IsMatch($Operation) }, 'First').Count -gt 0) { $clause }
                        })
                    $Compiled.ByOperation[$Operation] = $Candidates
                }
                foreach ($clause in $Candidates) {
                    try {
                        if (@($item).Where($clause.WhereBlock, 'First').Count -eq 0) { continue }
                    } catch {
                        Write-Warning "Error processing conditions: $($clause.CIPPClause): $($_.Exception.Message)"
                        continue
                    }
                    $item.CIPPAction = $clause.expectedAction
                    $item.CIPPBecActions = $clause.expectedBecActions
                    $item.CIPPClause = $clause.CIPPClause
                    $item | Add-Member -NotePropertyMembers ([ordered]@{
                            CIPPAlertComment      = $clause.AlertComment
                            CIPPCustomSubject     = $clause.CustomSubject
                            CIPPPsaTicketPriority = $clause.PsaTicketPriority
                        }) -Force -ErrorAction SilentlyContinue
                    $MatchedRules.Add($clause.CIPPClause)
                    $item
                    break
                }
            }
            foreach ($Matched in $DataToProcess) {
                if ($Matched.AuditRecord -isnot [string]) {
                    $Matched.AuditRecord = [string]([CIPP.CippJson]::ToJson($Matched.AuditRecord, 10) ?? (ConvertTo-Json -InputObject $Matched.AuditRecord -Compress -Depth 10))
                }
            }
            $Results.MatchedRules = @($MatchedRules | Select-Object -Unique)
            $Results.MatchedLogs = ($DataToProcess | Measure-Object).Count
            $Results.DataToProcess = $DataToProcess
        }

        if ($DataToProcess -and -not $EvaluateOnly) {
            $CippConfigTable = Get-CippTable -tablename Config
            $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
            $CIPPURL = 'https://{0}' -f $CippConfig.Value
            # Each alert's row is written as soon as its alert has gone out, replacing its Processing claim, so a crash
            # leaves at most the one alert being sent without its row. Alerts are few, so the per-row write is cheap; the
            # size guard still applies to rows that carry a large serialised alert.
            $AlertFlushCount = 1
            $AlertFlushBytes = 3MB
            $PendingAlertRows = [System.Collections.Generic.List[object]]::new()
            $PendingAlertBytes = 0
            $AuditLogTable = Get-CIPPTable -TableName 'AuditLogs'

            $FlushAlertRows = {
                if ($PendingAlertRows.Count -eq 0) { return }
                # Collapse rows sharing a key before the batch goes out. One pass can carry two
                # records with the same Id - Entra sign-in records reuse them - and the table module
                # silently keeps one of the duplicates. If that is the older event, the stored
                # EventCreationTime regresses and the newer event is replayable as 'newer' all over
                # again. Keep the greatest stamp; an absent stamp loses to any stamp.
                $RowsByKey = [ordered]@{}
                foreach ($Row in $PendingAlertRows) {
                    $Key = '{0}|{1}' -f $Row.PartitionKey, $Row.RowKey
                    $Kept = $RowsByKey[$Key]
                    if ($null -eq $Kept -or [string]$Row.EventCreationTime -gt [string]$Kept.EventCreationTime) {
                        $RowsByKey[$Key] = $Row
                    }
                }
                $BatchRows = @($RowsByKey.Values)
                try {
                    Add-CIPPAzDataTableEntity @AuditLogTable -Entity $BatchRows -Force
                } catch {
                    # Not fatal: the alerts themselves have already been dispatched, and the claim
                    # rows still prevent a retry from sending them again. What is lost is the stored
                    # copy, which shows in the UI as a row stuck at 'Processing'.
                    Write-Warning "Could not store $($BatchRows.Count) audit log row(s): $($_.Exception.Message)"
                }
                $PendingAlertRows.Clear()
            }

            # Each alert takes its own atomic claim (an insert, in Invoke-CippWebhookProcessing) just before it is sent:
            # the claim is the dedupe, and a crash leaves at most the alert being sent claimed but unsent.
            try {
                foreach ($AuditLog in $DataToProcess) {
                    try {
                        Invoke-CippWebhookProcessing -Data $AuditLog -CIPPURL ([string]$CIPPURL) -TenantFilter $TenantFilter -AlertComment $AuditLog.CIPPAlertComment -PendingAuditLogWrites $PendingAlertRows
                    } catch {
                        Write-Warning "Error sending final step of auditlog processing: $($_.Exception.Message)"
                        Write-Information $_.InvocationInfo.PositionMessage
                    }
                    if ($PendingAlertRows.Count -gt 0) {
                        $PendingAlertBytes = 0
                        foreach ($Row in $PendingAlertRows) { $PendingAlertBytes += $Row.Data.Length }
                        if ($PendingAlertRows.Count -ge $AlertFlushCount -or $PendingAlertBytes -ge $AlertFlushBytes) {
                            & $FlushAlertRows
                        }
                    }
                }
            } finally {
                # In a finally so an exception mid-loop still stores the rows for alerts that did
                # go out; only a hard process kill loses them.
                & $FlushAlertRows
            }
        }

        # Cache rows go once their alerts are out; a caller that sweeps its own partition deletes them all at the end.
        if (-not $EvaluateOnly -and -not $CallerSweepsCachePartition -and $PendingDeletes.Count -gt 0) {
            for ($DeleteStart = 0; $DeleteStart -lt $PendingDeletes.Count; $DeleteStart += $DeleteFlushSize) {
                $DeleteSlice = $PendingDeletes.GetRange($DeleteStart, [Math]::Min($DeleteFlushSize, $PendingDeletes.Count - $DeleteStart)).ToArray()
                try {
                    $null = Remove-CIPPAzDataTableEntity -Force @CacheWebhooksTable -Entity $DeleteSlice
                } catch {
                    Write-Information "Error removing $($DeleteSlice.Count) processed row(s) from cache: $($_.Exception.Message)"
                }
            }
        }

        # Belt-and-braces pass: re-resolve this chunk's ids to physical rows and delete anything the
        # per-record flush missed - in practice the parts of split records, since the flush deletes
        # by logical id only.
        #
        # Skipped when the caller sweeps its own partition, because it is not free: each slice of 50
        # ids becomes a 100-predicate "RowKey eq X or OriginalEntityId eq X" filter, and an OR-list
        # cannot be served from the Azure Table index - it scans the partition. That is ten scans per
        # call to find, normally, nothing at all. The caller's single keys-only partition pass
        # catches the same orphans for one point query.
        if (-not $CallerSweepsCachePartition -and -not $EvaluateOnly) {
            try {
                $RowIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Rows.id | Where-Object { $_ }))
                if ($RowIds.Count -gt 0) {
                # Only the rows being deleted, not a partition scan - this runs once per chunk.
                # Raw cmdlet and OriginalEntityId: the wrapper reports a split record's logical
                # RowKey, so deleting that left X-part1 / X-part2 orphaned.
                    $IdList = @($RowIds)
                    $FilterBatch = 50
                    $RowsToRemove = [System.Collections.Generic.List[object]]::new()

                    for ($Start = 0; $Start -lt $IdList.Count; $Start += $FilterBatch) {
                        $Slice = @($IdList[$Start..([Math]::Min($Start + $FilterBatch - 1, $IdList.Count - 1))])
                        $Predicate = ($Slice | ForEach-Object { "RowKey eq '$_' or OriginalEntityId eq '$_'" }) -join ' or '
                        $Found = @(Get-AzDataTableEntity @CacheWebhooksTable `
                                -Filter "PartitionKey eq '$CachePartitionKey' and ($Predicate)" `
                                -Property 'PartitionKey', 'RowKey')
                        foreach ($Row in $Found) {
                            $RowsToRemove.Add([PSCustomObject]@{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey })
                        }
                    }

                    if ($RowsToRemove.Count -gt 0) {
                        Remove-CIPPAzDataTableEntity @CacheWebhooksTable -Entity $RowsToRemove -Force
                        Write-Information "Removed $($RowsToRemove.Count) processed rows from cache"
                    }
                }
            } catch {
                Write-Information "Error removing rows from cache: $($_.Exception.Message)"
            }
        }

    } catch {
        $Results.Error = $_.Exception.Message
        Write-Warning "An error occurred during the Test-CIPPAuditLogRules execution: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }
    return $Results
}
