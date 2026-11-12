function Get-GraphToken {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $tenantid,
        $scope,
        $AsApp,
        $AppID,
        $AppSecret,
        $refreshToken,
        $ReturnRefresh,
        $SkipCache,
        [switch]$UseCertificate,
        [string]$RequireCloud
    )
    if (!$scope) { $scope = 'https://graph.microsoft.com/.default' }
    if (!$tenantid) { $tenantid = $env:TenantID }
    # The cache keys trim the tenant (CIPPTokenCache.BuildKey); the Tenants lookup below must see the same
    # value, or ' <id>' would share a government tenant's keys and cloud marker while resolving to the
    # partner cloud (redanthrax/CIPP#3).
    if ($tenantid -is [string]) { $tenantid = $tenantid.Trim() }

    # Certificate-exclusive auth: force the SAM certificate for CIPP's own SAM app tokens (app-only and
    # delegated). Scoped to the SAM app - explicit $AppID/$AppSecret callers use their own credentials.
    if ([System.Environment]::GetEnvironmentVariable('CertificateAuthMode') -and -not $AppID -and -not $AppSecret) {
        $UseCertificate = $true
    }
    # CIPP's own tokens (no explicit app credentials) follow the tenant's cloud; explicit callers do not.
    $SamApp = -not $AppID -and -not $AppSecret
    # -RequireCloud is passed only by the request helpers, only once they have chosen a government cloud's
    # hosts for the request (redanthrax/CIPP#3). It skips the commercial cache key, which can still hold a
    # token minted before the tenant's cloud changed in another worker, and returns only a token minted
    # for that cloud. Commercial callers never pass it and take exactly the path below as before.
    $RequireGovCloud = -not [string]::IsNullOrEmpty($RequireCloud) -and $RequireCloud -cne 'Commercial'
    if ($RequireGovCloud -and -not $SamApp) { throw 'A government cloud token can only be requested with CIPP''s own app credentials.' }

    $UseSharedTokenCache = ($SkipCache -ne $true) -and ($null -ne ('CIPP.CIPPTokenCache' -as [type]))

    # ── Fast path: check shared .NET token cache before any table lookups ──
    if ($UseSharedTokenCache) {
        $CacheClientId = if ($AppID) { [string]$AppID } else { [string]$env:ApplicationID }
        $GrantType = if ($asApp -eq $true -or ($null -ne $AppID -and $null -ne $AppSecret)) { 'client_credentials' } else { 'refresh_token' }
        if ($UseCertificate -eq $true) { $GrantType = "${GrantType}_certificate" }
        $SharedTokenCacheKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, [string]$scope, [bool]$asApp, $CacheClientId, $GrantType)
        if (-not $RequireGovCloud) {
            $SharedCacheEntry = [CIPP.CIPPTokenCache]::Lookup($SharedTokenCacheKey, 120)
            if ($SharedCacheEntry.Found -and -not [string]::IsNullOrWhiteSpace($SharedCacheEntry.TokenPayloadJson)) {
                try {
                    $AccessToken = $SharedCacheEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction Stop
                    if ($ReturnRefresh) { return $AccessToken }
                    return @{ Authorization = "Bearer $($AccessToken.access_token)" }
                } catch {
                    [CIPP.CIPPTokenCache]::Remove($SharedTokenCacheKey)
                }
            }
            $CachedFailure = [CIPP.CIPPTokenCache]::Lookup("$SharedTokenCacheKey|failed", 0)
            if ($CachedFailure.Found) { throw "Could not get token: $($CachedFailure.TokenPayloadJson)" }
        }

        # Government tenants (redanthrax/CIPP#2) are cached under their own cloud's key, never the
        # commercial one above. The slow path leaves a marker with the tenant's cloud so later calls
        # find that key without a table read. Commercial tenants have no marker.
        if ($SamApp) {
            $CloudMarkerKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, 'cipp-cloud-environment', $false, '', 'marker')
            $CloudMarker = [CIPP.CIPPTokenCache]::Lookup($CloudMarkerKey, 0)
            if ($CloudMarker.Found -and $CloudMarker.TokenPayloadJson -cne 'Commercial' -and (-not $RequireGovCloud -or $CloudMarker.TokenPayloadJson -ceq $RequireCloud)) {
                $FastRoute = Get-CIPPCloudTokenRoute -CloudEnvironment $CloudMarker.TokenPayloadJson -Scope $scope -CachedOnly
                if ($FastRoute) {
                    $FastGrantType = if ($asApp -eq $true) { 'client_credentials' } else { 'refresh_token' }
                    if ($FastRoute.UseCertificate -or ($UseCertificate -eq $true -and -not $FastRoute.UsesGovApp)) { $FastGrantType = "${FastGrantType}_certificate" }
                    $FastKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, [string]$FastRoute.Scope, [bool]$asApp, [string]$FastRoute.ClientId, "$FastGrantType@$($FastRoute.CloudEnvironment)")
                    $FastEntry = [CIPP.CIPPTokenCache]::Lookup($FastKey, 120)
                    if ($FastEntry.Found -and -not [string]::IsNullOrWhiteSpace($FastEntry.TokenPayloadJson)) {
                        try {
                            $AccessToken = $FastEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction Stop
                            if ($ReturnRefresh) { return $AccessToken }
                            return @{ Authorization = "Bearer $($AccessToken.access_token)" }
                        } catch {
                            [CIPP.CIPPTokenCache]::Remove($FastKey)
                        }
                    }
                    $CachedFailure = [CIPP.CIPPTokenCache]::Lookup("$FastKey|failed", 0)
                    if ($CachedFailure.Found) { throw "Could not get token: $($CachedFailure.TokenPayloadJson)" }
                }
            }
        }
    }

    # ── Slow path: need a new token — do table lookups + token acquisition ──
    # Acquire per-key lock to prevent thundering herd (multiple runspaces
    # all missing cache and independently fetching the same token).
    $LockAcquired = $false
    if ($UseSharedTokenCache -and $SharedTokenCacheKey) {
        # The key is rebuilt below once credentials and the tenant's cloud are known; release this one.
        $LockKey = $SharedTokenCacheKey
        $LockAcquired = [CIPP.CIPPTokenCache]::AcquireLock($LockKey, 30000)
        if ($LockAcquired -and -not $RequireGovCloud) {
            # Double-check: another thread may have stored the token while we waited
            $SharedCacheEntry = [CIPP.CIPPTokenCache]::Lookup($SharedTokenCacheKey, 120)
            if ($SharedCacheEntry.Found -and -not [string]::IsNullOrWhiteSpace($SharedCacheEntry.TokenPayloadJson)) {
                try {
                    $AccessToken = $SharedCacheEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction Stop
                    [CIPP.CIPPTokenCache]::ReleaseLock($LockKey)
                    $LockAcquired = $false
                    if ($ReturnRefresh) { return $AccessToken }
                    return @{ Authorization = "Bearer $($AccessToken.access_token)" }
                } catch {
                    [CIPP.CIPPTokenCache]::Remove($SharedTokenCacheKey)
                }
            }
            $CachedFailure = [CIPP.CIPPTokenCache]::Lookup("$SharedTokenCacheKey|failed", 0)
            if ($CachedFailure.Found) {
                [CIPP.CIPPTokenCache]::ReleaseLock($LockKey)
                $LockAcquired = $false
                throw "Could not get token: $($CachedFailure.TokenPayloadJson)"
            }
        }
    }
    try {
        if (!$env:SetFromProfile) { $CIPPAuth = Get-CIPPAuthentication; Write-Host 'Could not get Refreshtoken from environment variable. Reloading token.' }
        $ConfigTable = Get-CippTable -tablename 'Config'
        $Filter = "PartitionKey eq 'AppCache' and RowKey eq 'AppCache'"
        $AppCache = Get-CIPPAzDataTableEntity @ConfigTable -Filter $Filter
        #force auth update is appId is not the same as the one in the environment variable.
        if ($AppCache.ApplicationId -and $env:ApplicationID -ne $AppCache.ApplicationId) {
            $CIPPAuth = Get-CIPPAuthentication          # reload creds from KV (source of truth)
            if ($env:ApplicationID -and $env:ApplicationID -ne $AppCache.ApplicationId) {
                # KV and AppCache genuinely diverged — reconcile the marker to KV so we
                # don't reload on every subsequent token call.
                Write-Host "AppCache ApplicationId ($($AppCache.ApplicationId)) differs from KV ($env:ApplicationID); reconciling AppCache."
                $null = Add-CIPPAzDataTableEntity @ConfigTable -Entity @{
                    PartitionKey = 'AppCache'; RowKey = 'AppCache'; ApplicationId = "$env:ApplicationID"
                } -Force
            }
        }
        # Same ApplicationId but rotated secret, new refresh token or changed auth mode: writers bump
        # CredentialVersion (Set-CIPPCredentialVersion) and every other runspace reloads here.
        if ($AppCache.CredentialVersion -and $env:CIPPCredentialVersion -ne $AppCache.CredentialVersion) {
            $CIPPAuth = Get-CIPPAuthentication
            $env:CIPPCredentialVersion = [string]$AppCache.CredentialVersion
        }
        $refreshToken = $env:RefreshToken
        #Get list of tenants that have 'directTenant' set to true
        #get directtenants directly from table, avoid get-tenants due to performance issues
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        $Filter = "PartitionKey eq 'Tenants' and delegatedPrivilegeStatus eq 'directTenant'"
        $DirectTenantRows = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        $ClientType = $DirectTenantRows | Where-Object { $_.customerId -eq $tenantid -or $_.defaultDomainName -eq $tenantid }
        # A government direct tenant may also be addressed by its initialDomainName (e.g. contoso.onmicrosoft.us).
        # Only when nothing else matched, and only for a non-Commercial row, so commercial lookups are unchanged.
        # Same rule as Get-CIPPTenantRequestCloud, so the token and the API host agree (redanthrax/CIPP#2, #3).
        if (-not $ClientType) { $ClientType = $DirectTenantRows | Where-Object { $_.initialDomainName -and $_.initialDomainName -eq $tenantid -and $_.cloudEnvironment -and $_.cloudEnvironment -cne 'Commercial' } }
        if ($tenantid -ne $env:TenantID -and $clientType.delegatedPrivilegeStatus -eq 'directTenant') {
            Write-Host "Using direct tenant refresh token for $($clientType.customerId)"
            $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue

            if ($null -eq $ClientRefreshToken) {
                # Lazy load the refresh token from Key Vault only when needed
                Write-Host "Fetching refresh token for direct tenant $($clientType.customerId) from Key Vault"
                try {
                    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
                        # Development environment - get from table storage
                        $Table = Get-CIPPTable -tablename 'DevSecrets'
                        $Secret = Get-AzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
                        $secretname = $clientType.customerId -replace '-', '_'
                        if ($Secret.$secretname) {
                            Set-Item -Path "env:\$($clientType.customerId)" -Value $Secret.$secretname -Force
                            $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue
                        }
                    } else {
                        # Production environment - get from Key Vault
                        $keyvaultname = Get-CippKeyVaultName
                        $secret = Get-CippKeyVaultSecret -VaultName $keyvaultname -Name $clientType.customerId -AsPlainText -ErrorAction Stop
                        if ($secret) {
                            Set-Item -Path "env:\$($clientType.customerId)" -Value $secret -Force
                            $ClientRefreshToken = Get-Item -Path "env:\$($clientType.customerId)" -ErrorAction SilentlyContinue
                        }
                    }
                } catch {
                    Write-Host "Failed to retrieve refresh token for direct tenant $($clientType.customerId): $($_.Exception.Message)"
                }
            }

            $refreshToken = $ClientRefreshToken.Value
        } elseif ($tenantid -ne $env:TenantID) {
            # Multi-partner: use the owning partner's refresh token. No-op while the flag is off.
            $OwningPartner = Resolve-CIPPOwningPartner -TenantFilter $tenantid
            if ($OwningPartner -ne $env:TenantID) {
                $PartnerRefreshToken = Get-CIPPPartnerRefreshToken -PartnerTenantId $OwningPartner
                if ($PartnerRefreshToken) {
                    Write-Host "Using refresh token of partner tenant $OwningPartner for $tenantid"
                    $refreshToken = $PartnerRefreshToken
                } else {
                    Write-Host "No refresh token stored for partner tenant $OwningPartner - falling back to the primary partner token for $tenantid"
                }
            }
        }

        $AuthBody = @{
            client_id     = $env:ApplicationID
            client_secret = $env:ApplicationSecret
            scope         = $Scope
            refresh_token = $refreshToken
            grant_type    = 'refresh_token'
        }
        if ($asApp -eq $true) {
            $AuthBody = @{
                client_id     = $env:ApplicationID
                client_secret = $env:ApplicationSecret
                scope         = $Scope
                grant_type    = 'client_credentials'
            }
        }

        if ($null -ne $AppID -and $null -ne $refreshToken) {
            $AuthBody = @{
                client_id     = $appid
                refresh_token = $refreshToken
                scope         = $Scope
                grant_type    = 'refresh_token'
            }
        }

        if ($null -ne $AppID -and $null -ne $AppSecret) {
            $AuthBody = @{
                client_id     = $AppID
                client_secret = $AppSecret
                scope         = $Scope
                grant_type    = 'client_credentials'
            }
        }

        # Which cloud the tenant is in (redanthrax/CIPP#2). A direct tenant carries it on its row (read
        # above); the partner tenant and GDAP tenants are always in the partner cloud, as are rows that
        # predate the column. Commercial tenants on a commercial instance skip all of this.
        $CloudRoute = $null
        $LoginBase = 'https://login.microsoftonline.com'
        if ($SamApp) {
            $StoredCloud = if ($tenantid -ne $env:TenantID -and $clientType.delegatedPrivilegeStatus -eq 'directTenant') { [string](@($ClientType)[0].cloudEnvironment) } else { '' }
            $PartnerIsCommercial = [string]::IsNullOrEmpty($env:CIPP_PARTNER_CLOUD) -or $env:CIPP_PARTNER_CLOUD -ceq 'Commercial'
            $TenantCloud = if (-not [string]::IsNullOrEmpty($StoredCloud)) { $StoredCloud } elseif ($PartnerIsCommercial) { 'Commercial' } else { Get-CIPPPartnerCloudEnvironment }
            if (-not ($PartnerIsCommercial -and $TenantCloud -ceq 'Commercial')) {
                # Throws - before any token request - for an unknown cloud, a non-Graph scope on a
                # government tenant or a missing Azure Government app. Never falls back to commercial.
                $CloudRoute = Get-CIPPCloudTokenRoute -CloudEnvironment $TenantCloud -Scope $scope
                $scope = $CloudRoute.Scope
                $LoginBase = $CloudRoute.Authority
                $AuthBody.scope = $scope
                if ($CloudRoute.UsesGovApp) {
                    $GovCredential = Get-CIPPGovAppCredential
                    $AuthBody.client_id = $GovCredential.ApplicationId
                    $AuthBody.client_secret = $GovCredential.ApplicationSecret
                    $UseCertificate = $CloudRoute.UseCertificate
                }
            }
            # The marker is refreshed even with -SkipCache: the request helpers choose hosts from it
            # (Get-CIPPTenantRequestCloud), so a stale marker must never outlive a fresh table read here
            # and pair this token with another cloud's host (redanthrax/CIPP#3).
            if ($null -ne ('CIPP.CIPPTokenCache' -as [type])) {
                if (-not $CloudMarkerKey) { $CloudMarkerKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, 'cipp-cloud-environment', $false, '', 'marker') }
                # The cloud this worker last routed the tenant to. The cache is per worker, so after the tenant's
                # cloud changes in another worker this one can still hold tokens from the old cloud, and the
                # commercial key above is checked first. The first time a tenant is seen in a cloud, drop its
                # cached tokens so none can be paired with the new cloud's hosts (redanthrax/CIPP#3).
                $CloudSeenKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, 'cipp-cloud-environment', $false, '', 'seen')
                if ($CloudRoute) {
                    $CloudSeen = [CIPP.CIPPTokenCache]::Lookup($CloudSeenKey, 0)
                    if (-not ($CloudSeen.Found -and $CloudSeen.TokenPayloadJson -ceq $CloudRoute.CloudEnvironment)) { $null = [CIPP.CIPPTokenCache]::RemoveByTenant([string]$tenantid) }
                    [CIPP.CIPPTokenCache]::Store($CloudSeenKey, $CloudRoute.CloudEnvironment, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 86400)
                    [CIPP.CIPPTokenCache]::Store($CloudMarkerKey, $CloudRoute.CloudEnvironment, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
                } else {
                    [CIPP.CIPPTokenCache]::Remove($CloudMarkerKey)
                    [CIPP.CIPPTokenCache]::Remove($CloudSeenKey)
                }
            }
            # The request helper chose its hosts from a cloud the Tenants table no longer gives (the cloud
            # changed in another worker). The marker is now current; refuse rather than mint for another cloud.
            if ($RequireGovCloud -and (-not $CloudRoute -or $CloudRoute.CloudEnvironment -cne $RequireCloud)) {
                throw 'The tenant''s cloud environment changed while the request was prepared; nothing was sent. Try again.'
            }
        } elseif ($AuthBody.grant_type -eq 'refresh_token') {
            # An explicit -AppID without -AppSecret redeems a stored refresh token (a direct tenant's or the
            # partner's) at the commercial authority. Unless that token is commercial, refuse before any
            # request rather than send a government tenant's refresh token to the commercial host.
            $DirectRow = $tenantid -ne $env:TenantID -and $clientType.delegatedPrivilegeStatus -eq 'directTenant'
            $StoredCloud = if ($DirectRow) { [string](@($ClientType)[0].cloudEnvironment) } else { '' }
            $PartnerIsCommercial = [string]::IsNullOrEmpty($env:CIPP_PARTNER_CLOUD) -or $env:CIPP_PARTNER_CLOUD -ceq 'Commercial'
            $StoredTokenIsCommercial = if ($StoredCloud) { $StoredCloud -ceq 'Commercial' } else { $PartnerIsCommercial }
            if (-not $StoredTokenIsCommercial) {
                throw 'Explicit app credentials cannot redeem a government tenant''s stored refresh token (redanthrax/CIPP#2).'
            }
        }

        # Rebuild cache key after credential loading (env vars may have been set by Get-CIPPAuthentication)
        if ($UseSharedTokenCache) {
            $CacheClientId = if ($AppID) { [string]$AppID } elseif ($CloudRoute) { [string]$AuthBody.client_id } else { [string]$env:ApplicationID }
            $GrantType = if ($asApp -eq $true -or ($null -ne $AppID -and $null -ne $AppSecret)) { 'client_credentials' } else { 'refresh_token' }
            if ($UseCertificate -eq $true) { $GrantType = "${GrantType}_certificate" }
            # The cloud is part of every non-commercial key so tokens never cross clouds.
            if ($CloudRoute) { $GrantType = "$GrantType@$($CloudRoute.CloudEnvironment)" }
            $SharedTokenCacheKey = [CIPP.CIPPTokenCache]::BuildKey([string]$tenantid, [string]$scope, [bool]$asApp, $CacheClientId, $GrantType)
            if ($CloudRoute) {
                # The fast path may have missed this key (no marker yet); check it before asking Entra.
                $SharedCacheEntry = [CIPP.CIPPTokenCache]::Lookup($SharedTokenCacheKey, 120)
                if ($SharedCacheEntry.Found -and -not [string]::IsNullOrWhiteSpace($SharedCacheEntry.TokenPayloadJson)) {
                    $AccessToken = $SharedCacheEntry.TokenPayloadJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($AccessToken.access_token) {
                        if ($ReturnRefresh) { return $AccessToken }
                        return @{ Authorization = "Bearer $($AccessToken.access_token)" }
                    }
                }
                $CachedFailure = [CIPP.CIPPTokenCache]::Lookup("$SharedTokenCacheKey|failed", 0)
                if ($CachedFailure.Found) { throw "Could not get token: $($CachedFailure.TokenPayloadJson)" }
            }
        }

        try {
            if ($UseCertificate -eq $true) {
                if ($CloudRoute.UsesGovApp) {
                    $SAMCert = Get-CIPPSAMCertificate -Name 'GovSAMCertificate' -ErrorAction Stop
                    if ($SAMCert -and $SAMCert.PfxBase64 -ne $GovCredential.PfxBase64) { $SAMCert = Get-CIPPSAMCertificate -Name 'GovSAMCertificate' -SkipCache -ErrorAction Stop }
                    if (-not $SAMCert) { throw 'Azure Government app not configured: no certificate is stored for it.' }
                } else {
                    $SAMCert = Get-CIPPSAMCertificate -ErrorAction Stop
                    if (-not $SAMCert) { throw 'No SAM certificate available. Run Update-CIPPSAMCertificate to create one.' }
                }
            }
            for ($CertAttempt = 1; $CertAttempt -le 2; $CertAttempt++) {
                try {
                    if ($UseCertificate -eq $true -and $AuthBody.grant_type -eq 'client_credentials') {
                        # App-only with certificate: use the dedicated cert token function
                        # (has its own cache under the same key and the AADSTS700027 retry)
                        $CertSplat = @{ TenantId = $tenantid; AppId = $AuthBody.client_id; Scope = $scope; Certificate = $SAMCert.Certificate; SkipCache = ($SkipCache -eq $true) }
                        if ($CloudRoute) { $CertSplat.CloudEnvironment = $CloudRoute.CloudEnvironment }
                        $AccessToken = Get-GraphTokenFromCert @CertSplat -ErrorAction Stop
                        if (-not $AccessToken.access_token) { throw "Could not get a token using the SAM certificate for $tenantid" }
                    } else {
                        if ($UseCertificate -eq $true) {
                            # Delegated with certificate: authenticate the app with a signed assertion
                            # instead of the client secret; the refresh token still provides user context
                            $null = $AuthBody.Remove('client_secret')
                            $AuthBody.client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                            $AuthBody.client_assertion = if ($CloudRoute) {
                                New-CIPPCertificateAssertion -TenantId $tenantid -AppId $AuthBody.client_id -Certificate $SAMCert.Certificate -Audience "$LoginBase/$($tenantid)/oauth2/v2.0/token"
                            } else {
                                New-CIPPCertificateAssertion -TenantId $tenantid -AppId $AuthBody.client_id -Certificate $SAMCert.Certificate
                            }
                        }
                        $AccessToken = (Invoke-CIPPRestMethod -Method post -Uri "$LoginBase/$($tenantid)/oauth2/v2.0/token" -Body $Authbody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop)
                    }
                    if ($CertAttempt -gt 1 -and $SAMCert.PfxBase64) {
                        $CertificateName = if ($CloudRoute.UsesGovApp) { 'GovSAMCertificate' } else { 'SAMCertificate' }
                        Update-CIPPSAMCertificateEnvCache -Name $CertificateName -PfxBase64 $SAMCert.PfxBase64
                    }
                    break
                } catch {
                    # A cached certificate may no longer be registered on the app: retry once with the stored one.
                    $TokenError = $_
                    if ($UseCertificate -ne $true -or $CertAttempt -gt 1 -or "$($TokenError.ErrorDetails.Message) $($TokenError.Exception.Message)" -notmatch 'AADSTS700027') { throw $TokenError }
                    $StoredCert = try {
                        if ($CloudRoute.UsesGovApp) { Get-CIPPSAMCertificate -Name 'GovSAMCertificate' -SkipCache -ErrorAction Stop } else { Get-CIPPSAMCertificate -SkipCache -ErrorAction Stop }
                    } catch { $null }
                    if (-not $StoredCert -or $StoredCert.Thumbprint -eq $SAMCert.Thumbprint) { throw $TokenError }
                    $SAMCert = $StoredCert
                }
            }
            if ($null -eq $AccessToken.expires_on -and $AccessToken.expires_in) {
                $ExpiresOn = [int](Get-Date -UFormat %s -Millisecond 0) + $AccessToken.expires_in
                $AccessToken.PSObject.Properties.Remove('expires_on')
                $AccessToken.PSObject.Properties.Add([psnoteproperty]::new('expires_on', $ExpiresOn))
            }

            if ($UseSharedTokenCache -and $SharedTokenCacheKey) {
                try {
                    $TokenPayloadJson = $AccessToken | ConvertTo-Json -Depth 20 -Compress
                    [CIPP.CIPPTokenCache]::Store($SharedTokenCacheKey, $TokenPayloadJson, [int64]$AccessToken.expires_on)
                } catch {
                    # Ignore shared cache write failures
                }
            }

            if ($ReturnRefresh) { return $AccessToken }
            return @{ Authorization = "Bearer $($AccessToken.access_token)" }
        } catch {
            # Track consecutive Graph API failures
            $TenantsTable = Get-CippTable -tablename Tenants
            $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
            $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
            if (!$Tenant.RowKey) {
                $donotset = $true
                $Tenant = [pscustomobject]@{
                    LastGraphTokenError = ''
                    LastGraphError      = ''
                    PartitionKey        = 'TenantFailed'
                    RowKey              = 'Failed'
                }
            }
            $Tenant.LastGraphError = if ( $_.ErrorDetails.Message) {
                if (Test-Json $_.ErrorDetails.Message -ErrorAction SilentlyContinue) {
                    $msg = $_.ErrorDetails.Message | ConvertFrom-Json
                    "$($msg.error):$($msg.error_description)"
                } else {
                    "$($_.ErrorDetails.Message)"
                }
            } else {
                $_.Exception.Message
            }

            if (!$donotset) { Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant }
            # Errors that only an admin can fix: fail fast for 30 min instead of re-asking Entra on every call.
            # An invalid client secret (7000215) is the exception: a freshly rotated secret returns it
            # while Entra replicates, so it is only held for a minute.
            if ($UseSharedTokenCache -and $SharedTokenCacheKey -and $Tenant.LastGraphError -match 'AADSTS(7000215|7000222|700082|9002313|50173|700016|7000229|500014|500011|90002|50020|65001|50076|50079|53003)\b') {
                $FailureTtl = if ($Tenant.LastGraphError -match 'AADSTS7000215\b') { 60 } else { 1800 }
                [CIPP.CIPPTokenCache]::Store("$SharedTokenCacheKey|failed", [string]$Tenant.LastGraphError, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $FailureTtl)
            }
            throw "Could not get token: $($Tenant.LastGraphError)"
        }
    } finally {
        # Always release the per-key lock if we acquired it
        if ($LockAcquired -and $LockKey) {
            [CIPP.CIPPTokenCache]::ReleaseLock($LockKey)
        }
    }
}
