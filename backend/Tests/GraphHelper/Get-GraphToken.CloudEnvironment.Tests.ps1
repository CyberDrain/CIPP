# Token acquisition by cloud (redanthrax/CIPP#2). Pinned invariants:
#   - commercial tenants on a commercial instance take the exact pre-#2 path (no new reads or calls)
#   - a government tenant uses the government authority, the Azure Government app and the
#     government Graph scope, and its token is cached under a key that names the cloud
#   - missing/unknown configuration fails closed before any token request, never with commercial
#     credentials or hosts
#   - non-Graph scopes are refused for government tenants (#3 routes those hosts)

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CIPPTokenCache' -as [type])) {
        Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    }

    function Get-CIPPAuthentication { $true }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CIPPSAMCertificate { param($Name, [switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) }
    function Invoke-CIPPRestMethod { param($Method, $Uri, $Body, $ContentType, $Headers) }
    function Get-CippKeyVaultName {}
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Update-CIPPSAMCertificateEnvCache { param($Name, $PfxBase64) }
    function Get-CIPPGovAppCredential { param([switch]$Force) }
    # MultiPartner off: every GDAP tenant is owned by the primary partner, whose token is $env:RefreshToken.
    function Resolve-CIPPOwningPartner { param($TenantFilter) $env:TenantID }
    function Get-CIPPPartnerRefreshToken { param($PartnerTenantId) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphToken.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphTokenFromCert.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudEndpoint.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudScope.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudUri.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Resolve-CIPPCloudHost.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPPartnerCloudEnvironment.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudTokenRoute.ps1')

    $script:Partner = '11111111-2222-3333-4444-555555555555'
    $script:GovTenant = 'a0000000-0000-0000-0000-00000000000a'
    $script:ComTenant = 'c0000000-0000-0000-0000-00000000000c'
    $script:GdapTenant = 'd0000000-0000-0000-0000-00000000000d'
    $script:GovAppId = '9a9a9a9a-0000-0000-0000-000000000000'
    $script:EnvNames = 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SetFromProfile', 'CIPPCredentialVersion', 'CIPP_PARTNER_CLOUD', 'CIPPGovAppLoaded', $script:GovTenant, $script:ComTenant
}

Describe 'Get-GraphToken cloud routing' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        $script:SavedEnv = @{}
        foreach ($Name in $script:EnvNames) { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name); Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $env:TenantID = $script:Partner
        $env:RefreshToken = 'partner-refresh-token'
        $env:SetFromProfile = 'true'
        Set-Item "env:$($script:GovTenant)" 'gov-tenant-refresh-token'
        Set-Item "env:$($script:ComTenant)" 'com-tenant-refresh-token'

        $script:GovCloud = 'USGovHigh'
        $script:GovCred = [pscustomobject]@{ ApplicationId = $script:GovAppId; ApplicationSecret = 'gov-secret'; PfxBase64 = $null; HasSecret = $true; HasCertificate = $false; Configured = $true }

        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*directTenant*') {
                return @(
                    [pscustomobject]@{ customerId = $script:GovTenant; defaultDomainName = 'gov.us'; initialDomainName = 'gov.onmicrosoft.us'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = $script:GovCloud }
                    [pscustomobject]@{ customerId = $script:ComTenant; defaultDomainName = 'com.com'; initialDomainName = 'com.onmicrosoft.com'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'Commercial' }
                )
            }
            return $null
        }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Update-AzDataTableEntity {}
        Mock Get-CIPPGovAppCredential { $env:CIPPGovAppLoaded = 'true'; $script:GovCred }
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = $null; Thumbprint = 'GOV'; PfxBase64 = 'gov-pfx' } }
        Mock New-CIPPCertificateAssertion { 'signed.jwt' }
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ access_token = "token-for-$($Body.client_id)"; refresh_token = 'new-refresh'; expires_in = 3600 } }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue } else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    Context 'commercial instance' {
        It 'keeps a commercial direct tenant on the pre-#2 path' {
            $null = Get-GraphToken -tenantid $script:ComTenant

            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "https://login.microsoftonline.com/$($script:ComTenant)/oauth2/v2.0/token" -and
                $Body.client_id -eq 'sam-app-id' -and $Body.client_secret -eq 'sam-secret' -and
                $Body.scope -eq 'https://graph.microsoft.com/.default' -and $Body.refresh_token -eq 'com-tenant-refresh-token'
            }
            Should -Invoke Get-CIPPGovAppCredential -Times 0
        }

        It 'keeps a commercial direct tenant addressed by its initial domain on the pre-#2 path (partner token, as before)' {
            $null = Get-GraphToken -tenantid 'com.onmicrosoft.com'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://login.microsoftonline.com/com.onmicrosoft.com/oauth2/v2.0/token' -and
                $Body.client_id -eq 'sam-app-id' -and $Body.refresh_token -eq 'partner-refresh-token' -and
                $Body.scope -eq 'https://graph.microsoft.com/.default'
            }
            Should -Invoke Get-CIPPGovAppCredential -Times 0
        }

        It 'resolves a government direct tenant addressed by its initial domain to its own cloud and token (redanthrax/CIPP#2, #3)' {
            $Result = Get-GraphToken -tenantid 'gov.onmicrosoft.us'

            $Result.Authorization | Should -Be "Bearer token-for-$($script:GovAppId)"
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://login.microsoftonline.us/gov.onmicrosoft.us/oauth2/v2.0/token' -and
                $Body.client_id -eq $script:GovAppId -and $Body.refresh_token -eq 'gov-tenant-refresh-token' -and
                $Body.scope -eq 'https://graph.microsoft.us/.default'
            }
            # The marker it leaves is the one Get-CIPPTenantRequestCloud reads, so the API host agrees.
            $MarkerKey = [CIPP.CIPPTokenCache]::BuildKey('gov.onmicrosoft.us', 'cipp-cloud-environment', $false, '', 'marker')
            [CIPP.CIPPTokenCache]::Lookup($MarkerKey, 0).TokenPayloadJson | Should -BeExactly 'USGovHigh'
        }

        It 'keeps GDAP and partner tokens on the pre-#2 path, scope untouched' {
            $null = Get-GraphToken -tenantid $script:GdapTenant -scope 'https://outlook.office365.com/.default'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -like 'https://login.microsoftonline.com/*' -and $Body.refresh_token -eq 'partner-refresh-token' -and $Body.scope -eq 'https://outlook.office365.com/.default'
            }
            Should -Invoke Get-CIPPGovAppCredential -Times 0
        }

        It 'requests a <Cloud> token from the government authority with the Azure Government app' -TestCases @(
            @{ Cloud = 'USGovHigh'; Scope = 'https://graph.microsoft.us/.default' }
            @{ Cloud = 'USGovDoD'; Scope = 'https://dod-graph.microsoft.us/.default' }
        ) {
            param($Cloud, $Scope)
            $script:GovCloud = $Cloud

            $Result = Get-GraphToken -tenantid $script:GovTenant

            $Result.Authorization | Should -Be "Bearer token-for-$($script:GovAppId)"
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "https://login.microsoftonline.us/$($script:GovTenant)/oauth2/v2.0/token" -and
                $Body.client_id -eq $script:GovAppId -and $Body.client_secret -eq 'gov-secret' -and
                $Body.scope -eq $Scope -and $Body.refresh_token -eq 'gov-tenant-refresh-token' -and $Body.grant_type -eq 'refresh_token'
            }
        }

        It 'never sends a government tenant''s request to a commercial host or with SAM credentials' {
            $null = Get-GraphToken -tenantid $script:GovTenant
            $null = Get-GraphToken -tenantid 'gov.us' -AsApp $true
            Should -Invoke Invoke-CIPPRestMethod -Times 0 -ParameterFilter { $Uri -like '*microsoftonline.com*' -or $Body.client_id -eq 'sam-app-id' -or "$($Body.scope)" -like '*graph.microsoft.com*' -or $Body.client_secret -eq 'sam-secret' }
        }

        It 'treats a padded government tenant id as that tenant, not as the partner cloud (redanthrax/CIPP#3)' {
            # The cache key trims the id; the Tenants lookup must too, or the padded id would share the
            # tenant's keys and cloud marker while resolving to the commercial authority.
            $null = Get-GraphToken -tenantid " $($script:GovTenant) "
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://login.microsoftonline.us/$($script:GovTenant)/oauth2/v2.0/token" -and $Body.client_id -eq $script:GovAppId }
            Should -Invoke Invoke-CIPPRestMethod -Times 0 -ParameterFilter { $Uri -like '*microsoftonline.com*' }
            [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 0).TokenPayloadJson | Should -BeExactly 'USGovHigh'
        }

        It 'caches a government token under a key naming the cloud and serves it without another table read' {
            $null = Get-GraphToken -tenantid $script:GovTenant
            $Key = [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'https://graph.microsoft.us/.default', $false, $script:GovAppId, 'refresh_token@USGovHigh')
            [CIPP.CIPPTokenCache]::Lookup($Key, 0).Found | Should -BeTrue
            $CommercialKey = [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'https://graph.microsoft.com/.default', $false, 'sam-app-id', 'refresh_token')
            [CIPP.CIPPTokenCache]::Lookup($CommercialKey, 0).Found | Should -BeFalse

            $Second = Get-GraphToken -tenantid $script:GovTenant

            $Second.Authorization | Should -Be "Bearer token-for-$($script:GovAppId)"
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
            Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly   # AppCache + direct tenants, first call only
        }

        It 'serves a cached government token even when the cloud marker has gone' {
            $null = Get-GraphToken -tenantid $script:GovTenant
            [CIPP.CIPPTokenCache]::Remove([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'))
            $null = Get-GraphToken -tenantid $script:GovTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
        }

        It 'fails closed with "Azure Government app not configured" and makes no request' {
            $script:GovCred = [pscustomobject]@{ ApplicationId = $null; ApplicationSecret = $null; PfxBase64 = $null; HasSecret = $false; HasCertificate = $false; Configured = $false }
            { Get-GraphToken -tenantid $script:GovTenant } | Should -Throw '*Azure Government app not configured*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'fails closed for a stored cloud of <Value>' -TestCases @(
            @{ Value = 'usgovhigh' }
            @{ Value = 'USGov' }
            @{ Value = 'GCCHigh' }
        ) {
            param($Value)
            $script:GovCloud = $Value
            { Get-GraphToken -tenantid $script:GovTenant } | Should -Throw '*Unknown cloud environment*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'refuses a scope with no government host for a government tenant: <Scope>' -TestCases @(
            @{ Scope = 'https://api.partnercenter.microsoft.com/.default' }
            @{ Scope = 'https://ps.compliance.protection.outlook.com/.default' }
            @{ Scope = '48ac35b8-9aa8-4d74-927d-1f4a14a0b239/.default' }
        ) {
            param($Scope)
            { Get-GraphToken -tenantid $script:GovTenant -scope $Scope } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'also refuses such a scope on the cached fast path' {
            $null = Get-GraphToken -tenantid $script:GovTenant
            { Get-GraphToken -tenantid $script:GovTenant -scope 'https://api.partnercenter.microsoft.com/.default' } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
        }

        It 'requests the <Cloud> Exchange resource from the government authority (redanthrax/CIPP#3)' -TestCases @(
            @{ Cloud = 'USGovHigh'; Expected = 'https://outlook.office365.us/.default' }
            @{ Cloud = 'USGovDoD'; Expected = 'https://webmail.apps.mil/.default' }
        ) {
            param($Cloud, $Expected)
            $script:GovCloud = $Cloud
            $null = Get-GraphToken -tenantid $script:GovTenant -scope 'https://outlook.office365.com/.default'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -like 'https://login.microsoftonline.us/*' -and $Body.scope -eq $Expected -and $Body.client_id -eq $script:GovAppId
            }
        }

        It 'records an Entra failure on the government key, not the commercial one' {
            Mock Get-CIPPAzDataTableEntity {
                if ($Filter -like '*directTenant*') { return @([pscustomobject]@{ customerId = $script:GovTenant; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'USGovHigh' }) }
                if ($Filter -like '*Tenants*') { return [pscustomobject]@{ RowKey = 'r'; LastGraphError = ''; LastGraphTokenError = '' } }
            }
            Mock Invoke-CIPPRestMethod { throw 'invalid_grant:AADSTS50173: The provided grant has expired' }
            { Get-GraphToken -tenantid $script:GovTenant } | Should -Throw '*AADSTS50173*'
            $GovKey = [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'https://graph.microsoft.us/.default', $false, $script:GovAppId, 'refresh_token@USGovHigh')
            [CIPP.CIPPTokenCache]::Lookup("$GovKey|failed", 0).Found | Should -BeTrue
        }

        It 'returns the government refresh token to Start-UpdateTokensTimer, fresh and from the cache' {
            # The timer calls Get-GraphToken -ReturnRefresh $true -TenantId <direct tenant> and stores
            # refresh_token back in Key Vault under the tenant id.
            $First = Get-GraphToken -ReturnRefresh $true -TenantId $script:GovTenant
            $First.refresh_token | Should -Be 'new-refresh'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -like 'https://login.microsoftonline.us/*' -and $Body.refresh_token -eq 'gov-tenant-refresh-token' -and $Body.client_id -eq $script:GovAppId
            }
            $Second = Get-GraphToken -ReturnRefresh $true -TenantId $script:GovTenant
            $Second.refresh_token | Should -Be 'new-refresh'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
        }

        It 'never serves one cloud''s cached token for another, even with the old token still cached' {
            $null = Get-GraphToken -tenantid $script:GovTenant   # USGovHigh token cached + marker
            $script:GovCloud = 'USGovDoD'
            # Only the marker goes (e.g. it expired); the GCC High token is still in the cache.
            [CIPP.CIPPTokenCache]::Remove([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'))

            $null = Get-GraphToken -tenantid $script:GovTenant

            Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Body.scope -eq 'https://dod-graph.microsoft.us/.default' }
            [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'https://graph.microsoft.us/.default', $false, $script:GovAppId, 'refresh_token@USGovHigh') |
                Should -Not -Be ([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'https://dod-graph.microsoft.us/.default', $false, $script:GovAppId, 'refresh_token@USGovDoD'))
        }

        It 'picks up a changed cloud at once when the tenant''s cache is cleared (cloud override, token removal)' {
            $null = Get-GraphToken -tenantid $script:GovTenant
            $script:GovCloud = 'Commercial'
            $null = [CIPP.CIPPTokenCache]::RemoveByTenant($script:GovTenant)   # what Clear-CippTokenCache -TenantFilter does

            $null = Get-GraphToken -tenantid $script:GovTenant

            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "https://login.microsoftonline.com/$($script:GovTenant)/oauth2/v2.0/token" -and $Body.client_id -eq 'sam-app-id' -and $Body.scope -eq 'https://graph.microsoft.com/.default'
            }
            [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 0).Found | Should -BeFalse
        }

        It 'keeps serving the old cloud''s token until the marker expires when the cache is NOT cleared (another worker)' {
            # Documents the cross-worker window: Invoke-EditTenantCloudEnvironment clears only its own
            # process's cache, so another worker follows the 15-minute marker until it expires.
            $null = Get-GraphToken -tenantid $script:GovTenant
            $script:GovCloud = 'USGovDoD'
            $null = Get-GraphToken -tenantid $script:GovTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
            $Marker = [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 0)
            $Marker.TokenPayloadJson | Should -BeExactly 'USGovHigh'
        }

        It 'drops a commercial token another worker cached once a request sees the tenant is now government (redanthrax/CIPP#3)' {
            # Worker B: the tenant was Commercial and B cached a commercial token. Its cloud is changed to
            # USGovHigh in another worker, so B's cache is not cleared. When B's request helpers next read the
            # table (marker expired), the commercial token must go, so the next token is the government one.
            . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTenantRequestCloud.ps1')
            $script:GovCloud = 'Commercial'
            $null = Get-GraphToken -tenantid $script:GovTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Uri -like 'https://login.microsoftonline.com/*' }
            $script:GovCloud = 'USGovHigh'
            [CIPP.CIPPTokenCache]::Remove([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'))

            Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly 'USGovHigh'
            $Result = Get-GraphToken -tenantid $script:GovTenant

            $Result.Authorization | Should -Be "Bearer token-for-$($script:GovAppId)"
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Uri -like 'https://login.microsoftonline.us/*' -and $Body.scope -eq 'https://graph.microsoft.us/.default' }
        }

        It 'drops a commercial token cached for another scope when a token request finds the tenant is now government' {
            $script:GovCloud = 'Commercial'
            $null = Get-GraphToken -tenantid $script:GovTenant                    # delegated commercial token cached
            $script:GovCloud = 'USGovHigh'
            $null = Get-GraphToken -tenantid $script:GovTenant -AsApp $true       # another key: reads the table, finds USGovHigh

            $Result = Get-GraphToken -tenantid $script:GovTenant                  # must not be the cached commercial one
            $Result.Authorization | Should -Be "Bearer token-for-$($script:GovAppId)"
            Should -Invoke Invoke-CIPPRestMethod -Times 3 -Exactly
            Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly -ParameterFilter { $Uri -like 'https://login.microsoftonline.us/*' }
        }

        It 'drops a government tenant''s cached tokens only the first time it is seen in its cloud' {
            . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTenantRequestCloud.ps1')
            $null = Get-GraphToken -tenantid $script:GovTenant
            $MarkerKey = [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker')
            # Marker expiry, then a token call and a request-cloud read: the government token stays cached.
            [CIPP.CIPPTokenCache]::Remove($MarkerKey)
            $null = Get-GraphToken -tenantid $script:GovTenant
            [CIPP.CIPPTokenCache]::Remove($MarkerKey)
            Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly 'USGovHigh'
            $null = Get-GraphToken -tenantid $script:GovTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
        }

        It 'leaves a commercial tenant''s cached token alone when the request cloud is read from the table' {
            . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTenantRequestCloud.ps1')
            $null = Get-GraphToken -tenantid $script:ComTenant
            Get-CIPPTenantRequestCloud -TenantFilter $script:ComTenant | Should -BeExactly 'Commercial'
            $null = Get-GraphToken -tenantid $script:ComTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
            [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:ComTenant, 'cipp-cloud-environment', $false, '', 'seen'), 0).Found | Should -BeFalse
        }

        It 'refreshes a stale cloud marker on a -SkipCache request, so the request host follows the token (<From> -> <To>)' -TestCases @(
            @{ From = 'Commercial'; To = 'USGovHigh'; Scope = 'https://graph.microsoft.us/.default' }
            @{ From = 'USGovHigh'; To = 'Commercial'; Scope = 'https://graph.microsoft.com/.default' }
        ) {
            param($From, $To, $Scope)
            # Another worker cached the old cloud for this tenant before its cloud changed (redanthrax/CIPP#3):
            # a -SkipCache token reads the table afresh, and the request helpers must not then pick a host
            # from the old marker (a government token sent to graph.microsoft.com, or the reverse).
            . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTenantRequestCloud.ps1')
            $MarkerKey = [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker')
            [CIPP.CIPPTokenCache]::Store($MarkerKey, $From, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
            $script:GovCloud = $To

            $null = Get-GraphToken -tenantid $script:GovTenant -SkipCache $true

            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Body.scope -eq $Scope }
            Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly $To
        }
    }

    Context 'Azure Government app with a certificate' {
        BeforeEach {
            $script:GovCred = [pscustomobject]@{ ApplicationId = $script:GovAppId; ApplicationSecret = $null; PfxBase64 = 'gov-pfx'; HasSecret = $false; HasCertificate = $true; Configured = $true }
            Mock Get-GraphTokenFromCert { [pscustomobject]@{ access_token = 'gov-cert-token'; expires_in = 3600 } }
            $Rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $Req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=gov', $Rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $script:GovCert = $Req.CreateSelfSigned([datetimeoffset]::UtcNow.AddDays(-1), [datetimeoffset]::UtcNow.AddDays(1))
            Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = $script:GovCert; Thumbprint = 'GOV'; PfxBase64 = 'gov-pfx' } }
        }

        It 'signs a delegated request with the government certificate for the government audience' {
            $null = Get-GraphToken -tenantid $script:GovTenant
            Should -Invoke Get-CIPPSAMCertificate -ParameterFilter { $Name -eq 'GovSAMCertificate' }
            Should -Invoke Get-CIPPSAMCertificate -Times 0 -ParameterFilter { $Name -ne 'GovSAMCertificate' }
            Should -Invoke New-CIPPCertificateAssertion -Times 1 -ParameterFilter { $AppId -eq $script:GovAppId -and $Audience -eq "https://login.microsoftonline.us/$($script:GovTenant)/oauth2/v2.0/token" }
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -ParameterFilter { $Body.client_assertion -eq 'signed.jwt' -and -not $Body.client_secret -and $Uri -like 'https://login.microsoftonline.us/*' }
        }

        It 'requests an app-only token through Get-GraphTokenFromCert with the cloud' {
            $Result = Get-GraphToken -tenantid $script:GovTenant -AsApp $true
            $Result.Authorization | Should -Be 'Bearer gov-cert-token'
            Should -Invoke Get-GraphTokenFromCert -Times 1 -ParameterFilter { $CloudEnvironment -eq 'USGovHigh' -and $AppId -eq $script:GovAppId -and $Scope -eq 'https://graph.microsoft.us/.default' }
        }

        It 'uses the certificate in certificate mode even when a secret exists' {
            $env:CertificateAuthMode = $true
            $script:GovCred.ApplicationSecret = 'gov-secret'; $script:GovCred.HasSecret = $true
            $null = Get-GraphToken -tenantid $script:GovTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -ParameterFilter { $Body.client_assertion -and -not $Body.client_secret }
        }

        It 'fails closed in certificate mode when the government app has only a secret' {
            $env:CertificateAuthMode = $true
            $script:GovCred = [pscustomobject]@{ ApplicationId = $script:GovAppId; ApplicationSecret = 'gov-secret'; PfxBase64 = $null; HasSecret = $true; HasCertificate = $false; Configured = $true }
            { Get-GraphToken -tenantid $script:GovTenant } | Should -Throw '*no certificate*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }
    }

    Context 'partner cloud setting' {
        It 'routes GDAP tenants of a GCC High partner through the SAM app at the government authority' {
            $env:CIPP_PARTNER_CLOUD = 'USGovHigh'
            $null = Get-GraphToken -tenantid $script:GdapTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "https://login.microsoftonline.us/$($script:GdapTenant)/oauth2/v2.0/token" -and
                $Body.client_id -eq 'sam-app-id' -and $Body.refresh_token -eq 'partner-refresh-token' -and $Body.scope -eq 'https://graph.microsoft.us/.default'
            }
            Should -Invoke Get-CIPPGovAppCredential -Times 0
        }

        It 'refuses a commercial direct tenant on a government instance' {
            $env:CIPP_PARTNER_CLOUD = 'USGovHigh'
            { Get-GraphToken -tenantid $script:ComTenant } | Should -Throw '*not supported*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'fails closed for an invalid partner cloud setting' {
            $env:CIPP_PARTNER_CLOUD = 'usgovhigh'
            { Get-GraphToken -tenantid $script:GdapTenant } | Should -Throw '*CIPP_PARTNER_CLOUD*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'treats an explicit Commercial setting like the default' {
            $env:CIPP_PARTNER_CLOUD = 'Commercial'
            $null = Get-GraphToken -tenantid $script:GdapTenant
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -ParameterFilter { $Uri -like 'https://login.microsoftonline.com/*' -and $Body.client_id -eq 'sam-app-id' }
        }
    }

    Context 'explicit app credentials' {
        It 'leaves callers passing their own AppID/AppSecret on their own credentials' {
            $null = Get-GraphToken -tenantid $script:GovTenant -AppID 'other-app' -AppSecret 'other-secret'
            Should -Invoke Get-CIPPGovAppCredential -Times 0
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -ParameterFilter { $Body.client_id -eq 'other-app' }
        }

        It 'refuses to redeem a government direct tenant''s stored refresh token with an explicit AppID' {
            { Get-GraphToken -tenantid $script:GovTenant -AppID 'other-app' } | Should -Throw '*government*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'refuses to redeem the partner refresh token with an explicit AppID on a government instance' {
            $env:CIPP_PARTNER_CLOUD = 'USGovHigh'
            { Get-GraphToken -tenantid $script:GdapTenant -AppID 'other-app' } | Should -Throw '*government*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'still redeems a commercial refresh token with an explicit AppID at the commercial authority' {
            $null = Get-GraphToken -tenantid $script:ComTenant -AppID 'other-app'
            Should -Invoke Invoke-CIPPRestMethod -Times 1 -ParameterFilter {
                $Uri -like 'https://login.microsoftonline.com/*' -and $Body.client_id -eq 'other-app' -and $Body.refresh_token -eq 'com-tenant-refresh-token'
            }
        }
    }
}

Describe 'Get-GraphTokenFromCert cloud' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        Mock New-CIPPCertificateAssertion { 'signed.jwt' }
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ access_token = 'tok'; expires_in = 3600 } }
        $Rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $Req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=t', $Rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $script:Cert = $Req.CreateSelfSigned([datetimeoffset]::UtcNow.AddDays(-1), [datetimeoffset]::UtcNow.AddDays(1))
    }

    It 'keeps the commercial authority and key when no cloud is passed' {
        $null = Get-GraphTokenFromCert -TenantId 't1' -AppId 'a' -Certificate $script:Cert
        Should -Invoke Invoke-CIPPRestMethod -ParameterFilter { $Uri -eq 'https://login.microsoftonline.com/t1/oauth2/v2.0/token' }
        Should -Invoke New-CIPPCertificateAssertion -ParameterFilter { -not $Audience }
        [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey('t1', 'https://graph.microsoft.com/.default', $true, 'a', 'client_credentials_certificate'), 0).Found | Should -BeTrue
    }

    It 'uses the <Cloud> authority, audience and a cloud-specific key' -TestCases @(@{ Cloud = 'USGovHigh' }, @{ Cloud = 'USGovDoD' }) {
        param($Cloud)
        $null = Get-GraphTokenFromCert -TenantId 't1' -AppId 'a' -Scope 'https://graph.microsoft.us/.default' -Certificate $script:Cert -CloudEnvironment $Cloud
        Should -Invoke Invoke-CIPPRestMethod -ParameterFilter { $Uri -eq 'https://login.microsoftonline.us/t1/oauth2/v2.0/token' }
        Should -Invoke New-CIPPCertificateAssertion -ParameterFilter { $Audience -eq 'https://login.microsoftonline.us/t1/oauth2/v2.0/token' }
        [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey('t1', 'https://graph.microsoft.us/.default', $true, 'a', "client_credentials_certificate@$Cloud"), 0).Found | Should -BeTrue
    }

    It 'throws for an unknown cloud without a request' {
        { Get-GraphTokenFromCert -TenantId 't1' -AppId 'a' -Certificate $script:Cert -CloudEnvironment 'usgovhigh' } | Should -Throw '*Unknown cloud environment*'
        Should -Invoke Invoke-CIPPRestMethod -Times 0
    }
}
