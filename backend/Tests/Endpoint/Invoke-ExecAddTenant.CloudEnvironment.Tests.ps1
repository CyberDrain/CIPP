# Pester tests for the cloud environment recorded by Invoke-ExecAddTenant
#
# #1: a new direct tenant stores a cloud; the GDAP-conversion branch writes nothing.
# #2: the consent token's cloud (audience/issuer) must agree with the cloud picked in the UI; Graph is
# called on that cloud's host; discovery must agree on commercial vs government (reject otherwise,
# discarding the stored token); for GCC High vs DoD the token wins. A refresh of an existing direct
# tenant must be for the stored cloud. Government tenants skip the permission push.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAddTenant.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecAddTenant.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAuthentication { }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPDirectTenantToken { param($TenantId) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantid, $message, $Sev, $LogData) }
    function New-CippQueueEntry { param($Name, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value -replace "'", "''" }
    function Get-CIPPTenantCloudEnvironment { param($TenantId, $InitialDomainName) }
    function Clear-CippTokenCache { param($TenantFilter) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudEndpoint.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPAccessTokenCloudEnvironment.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPPartnerCloudEnvironment.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Resolve-CIPPSignInCloud.ps1')

    $script:Audience = @{ Commercial = 'https://graph.microsoft.com'; USGovHigh = 'https://graph.microsoft.us'; USGovDoD = 'https://dod-graph.microsoft.us' }
    function New-TestJwt {
        param([hashtable]$Claims)
        $Encode = { param($Text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
        '{0}.{1}.sig' -f (& $Encode '{"alg":"RS256"}'), (& $Encode ($Claims | ConvertTo-Json -Compress))
    }

    $script:TenantId = 'cccccccc-1111-2222-3333-444444444444'

    function New-AddRequest {
        param(
            # Cloud picked in the UI (sent as cloudEnvironment); $null sends nothing (pre-#2 clients)
            $Cloud = 'USGovHigh',
            # Cloud the token is for; defaults to the picked one
            $TokenCloud,
            $Issuer = 'https://sts.windows.net/x/',
            $AccessToken
        )
        if (-not $TokenCloud) { $TokenCloud = if ($Cloud) { $Cloud } else { 'Commercial' } }
        if (-not $AccessToken) { $AccessToken = New-TestJwt @{ aud = $script:Audience[$TokenCloud]; iss = $Issuer; tid = $script:TenantId } }
        $Body = [pscustomobject]@{
            tenantId          = $script:TenantId
            defaultDomainName = 'contoso.us'
            accessToken       = $AccessToken
            username          = 'admin@contoso.onmicrosoft.us'
        }
        if ($null -ne $Cloud) { $Body | Add-Member -NotePropertyName cloudEnvironment -NotePropertyValue $Cloud }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAddTenant' }
            Headers = @{ }
            Body    = $Body
            Query   = [pscustomobject]@{ }
        }
    }

    function New-GraphBatchResponse {
        param($InitialDomain = 'contoso.onmicrosoft.us')
        [pscustomobject]@{
            responses = @(
                [pscustomobject]@{ id = 'organization'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:TenantId; displayName = 'Contoso Gov' }) } }
                [pscustomobject]@{ id = 'domains'; body = [pscustomobject]@{ value = @(
                            [pscustomobject]@{ id = 'contoso.us'; isDefault = $true; isInitial = $false }
                            [pscustomobject]@{ id = $InitialDomain; isDefault = $false; isInitial = $true }
                        )
                    }
                }
            )
        }
    }
}

Describe 'Invoke-ExecAddTenant cloud environment' {
    AfterAll { Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue }

    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:ExistingTenant = $null
        Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue

        Mock Test-CIPPAccess { @('AllTenants') }
        Mock Get-CippTable { @{ Context = $tablename } }
        Mock Get-CIPPAuthentication {}
        Mock Get-CIPPAzDataTableEntity { $script:ExistingTenant }
        Mock Add-CIPPAzDataTableEntity { $script:Written.Add($Entity) }
        Mock Remove-CIPPDirectTenantToken {}
        Mock Write-LogMessage {}
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock Start-CIPPOrchestrator {}
        Mock Invoke-RestMethod { New-GraphBatchResponse }
        Mock Get-CIPPTenantCloudEnvironment { 'USGovHigh' }
    }

    Context 'new tenant' {
        It 'stores <Value> when the token and discovery agree' -TestCases @(
            @{ Value = 'Commercial' }
            @{ Value = 'USGovHigh' }
            @{ Value = 'USGovDoD' }
        ) {
            param($Value)
            Mock Get-CIPPTenantCloudEnvironment { $Value }

            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $Value)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $script:Written.Count | Should -Be 1
            $script:Written[0].cloudEnvironment | Should -BeExactly $Value
            $script:Written[0].delegatedPrivilegeStatus | Should -Be 'directTenant'
        }

        It 'calls Graph for a <Cloud> token on <GraphHost> only' -TestCases @(
            @{ Cloud = 'Commercial'; GraphHost = 'graph.microsoft.com' }
            @{ Cloud = 'USGovHigh'; GraphHost = 'graph.microsoft.us' }
            @{ Cloud = 'USGovDoD'; GraphHost = 'dod-graph.microsoft.us' }
        ) {
            param($Cloud, $GraphHost)
            Mock Get-CIPPTenantCloudEnvironment { $Cloud }
            $null = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $Cloud)
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://$GraphHost/v1.0/`$batch" }
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }

        It 'accepts a pre-#2 request with no cloudEnvironment and a commercial token' {
            Mock Get-CIPPTenantCloudEnvironment { 'Commercial' }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $null)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $script:Written[0].cloudEnvironment | Should -BeExactly 'Commercial'
            Should -Invoke Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://graph.microsoft.com/v1.0/$batch' }
            Should -Invoke Start-CIPPOrchestrator -Times 1
        }

        It 'passes the tenant id and the initial domain from Graph to detection' {
            $null = Invoke-ExecAddTenant -Request (New-AddRequest)
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 1 -ParameterFilter {
                $TenantId -eq $script:TenantId -and $InitialDomainName -eq 'contoso.onmicrosoft.us'
            }
        }

        It 'keeps the token''s <TokenCloud> when discovery says <Detected>' -TestCases @(
            @{ TokenCloud = 'USGovDoD'; Detected = 'USGovHigh' }
            @{ TokenCloud = 'USGovHigh'; Detected = 'USGovDoD' }
        ) {
            param($TokenCloud, $Detected)
            Mock Get-CIPPTenantCloudEnvironment { $Detected }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $TokenCloud)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $script:Written[0].cloudEnvironment | Should -BeExactly $TokenCloud
            Should -Invoke Write-LogMessage -ParameterFilter { $message -like "*Discovery reports $Detected*Storing $TokenCloud*" }
        }

        It 'rejects and discards the token when the token is <TokenCloud> but discovery says <Detected>' -TestCases @(
            @{ TokenCloud = 'USGovHigh'; Detected = 'Commercial' }
            @{ TokenCloud = 'USGovDoD'; Detected = 'Commercial' }
            @{ TokenCloud = 'Commercial'; Detected = 'USGovHigh' }
            @{ TokenCloud = 'Commercial'; Detected = 'USGovDoD' }
        ) {
            param($TokenCloud, $Detected)
            Mock Get-CIPPTenantCloudEnvironment { $Detected }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $TokenCloud)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.severity | Should -Be 'error'
            $script:Written.Count | Should -Be 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 1 -ParameterFilter { $TenantId -eq $script:TenantId }
            Should -Invoke Start-CIPPOrchestrator -Times 0
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*Blocked adding tenant*discovery*' }
        }

        It 'stores the token''s cloud when detection throws' {
            Mock Get-CIPPTenantCloudEnvironment { throw 'detection exploded' }

            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovDoD')

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $script:Written[0].cloudEnvironment | Should -BeExactly 'USGovDoD'
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*using USGovDoD from the sign-in token*' }
        }

        It 'does not detect or write when the Graph lookup fails' {
            Mock Invoke-RestMethod { throw 'unauthorized' }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
            $script:Written.Count | Should -Be 0
        }

        It 'skips the permission push for a government tenant and queues it for a commercial one' {
            Mock Get-CIPPTenantCloudEnvironment { 'USGovHigh' }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovHigh')
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Start-CIPPOrchestrator -Times 0
            Should -Invoke Write-LogMessage -ParameterFilter { $message -like '*Skipped the permission push*' }

            Mock Get-CIPPTenantCloudEnvironment { 'Commercial' }
            $null = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'Commercial')
            Should -Invoke Start-CIPPOrchestrator -Times 1
        }
    }

    Context 'token cloud must match the selected cloud' {
        It 'rejects <Name> before calling Graph, and discards the stored token' -TestCases @(
            @{ Name = 'a GCC High token for a Commercial selection'; Cloud = 'Commercial'; TokenCloud = 'USGovHigh' }
            @{ Name = 'a commercial token for a GCC High selection'; Cloud = 'USGovHigh'; TokenCloud = 'Commercial' }
            @{ Name = 'a GCC High token for a DoD selection'; Cloud = 'USGovDoD'; TokenCloud = 'USGovHigh' }
            @{ Name = 'a GCC High token with no selection'; Cloud = $null; TokenCloud = 'USGovHigh' }
            @{ Name = 'a miscased selection'; Cloud = 'usgovhigh'; TokenCloud = 'USGovHigh' }
            @{ Name = 'an unknown selection'; Cloud = 'GCCHigh'; TokenCloud = 'USGovHigh' }
        ) {
            param($Name, $Cloud, $TokenCloud)
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $Cloud -TokenCloud $TokenCloud)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Invoke-RestMethod -Times 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 1 -ParameterFilter { $TenantId -eq $script:TenantId }
            $script:Written.Count | Should -Be 0
        }

        It 'rejects a v2 token from the commercial authority for a government selection' {
            $Token = New-TestJwt @{ aud = '00000003-0000-0000-c000-000000000000'; iss = 'https://login.microsoftonline.com/x/v2.0' }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovHigh' -AccessToken $Token)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'rejects <Name>' -TestCases @(
            @{ Name = 'a token that is not a JWT'; Claims = $null }
            @{ Name = 'a token for an unknown audience'; Claims = @{ aud = 'https://graph.microsoft.de'; iss = 'https://sts.windows.net/x/' } }
            @{ Name = 'a token from an unknown issuer'; Claims = @{ aud = 'https://graph.microsoft.us'; iss = 'https://login.evil.example/x/' } }
        ) {
            param($Name, $Claims)
            $Token = if ($Claims) { New-TestJwt $Claims } else { 'token' }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -AccessToken $Token)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Invoke-RestMethod -Times 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 1
        }
    }

    Context 'token tenant must match the requested tenant' {
        It 'rejects a token for <Name> without detecting or writing' -TestCases @(
            @{ Name = 'a different tenant'; OrgId = 'dddddddd-1111-2222-3333-444444444444' }
            @{ Name = 'no organization id'; OrgId = $null }
            @{ Name = 'an empty organization id'; OrgId = '' }
        ) {
            param($Name, $OrgId)
            $script:OrgId = $OrgId
            Mock Invoke-RestMethod {
                $Batch = New-GraphBatchResponse
                $Batch.responses[0].body.value[0].id = $script:OrgId
                $Batch
            }

            $Response = Invoke-ExecAddTenant -Request (New-AddRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.severity | Should -Be 'error'
            $script:Written.Count | Should -Be 0
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
            Should -Invoke Start-CIPPOrchestrator -Times 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 1 -ParameterFilter { $TenantId -eq $script:TenantId }
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*Blocked adding tenant*' }
        }

        It 'accepts a token whose organization id matches the requested tenant' {
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Remove-CIPPDirectTenantToken -Times 0
        }
    }

    Context 'existing direct tenant' {
        It 'refreshes credentials without detecting or changing the stored cloud' {
            $script:ExistingTenant = [pscustomobject]@{
                PartitionKey = 'Tenants'; RowKey = $script:TenantId; customerId = $script:TenantId
                displayName = 'Contoso Gov'; defaultDomainName = 'contoso.us'
                delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'USGovDoD'
            }

            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovDoD')

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 0
            $script:Written.Count | Should -Be 1
            $script:Written[0].cloudEnvironment | Should -Be 'USGovDoD'
            $script:Written[0].directTenantUserPrincipalName | Should -Be 'admin@contoso.onmicrosoft.us'
        }

        It 'rejects a refresh signed in to <TokenCloud> for a tenant stored as <Stored> (partner <Partner>), keeping the stored token' -TestCases @(
            @{ Stored = 'USGovDoD'; TokenCloud = 'USGovHigh'; Partner = $null; Remedy = 'change the tenant''s cloud environment first' }
            @{ Stored = 'USGovHigh'; TokenCloud = 'Commercial'; Partner = $null; Remedy = 'remove the tenant and add it again in Commercial' }
            @{ Stored = 'Commercial'; TokenCloud = 'USGovHigh'; Partner = $null; Remedy = 'remove the tenant and add it again in USGovHigh' }
            @{ Stored = $null; TokenCloud = 'USGovHigh'; Partner = $null; Remedy = 'remove the tenant and add it again in USGovHigh' }
            @{ Stored = $null; TokenCloud = 'USGovDoD'; Partner = 'USGovHigh'; Remedy = 'change the tenant''s cloud environment first' }
        ) {
            param($Stored, $TokenCloud, $Partner, $Remedy)
            if ($Partner) { $env:CIPP_PARTNER_CLOUD = $Partner }
            $script:ExistingTenant = [pscustomobject]@{
                PartitionKey = 'Tenants'; RowKey = $script:TenantId; customerId = $script:TenantId
                displayName = 'Contoso'; defaultDomainName = 'contoso.us'; delegatedPrivilegeStatus = 'directTenant'
            }
            if ($Stored) { $script:ExistingTenant | Add-Member -NotePropertyName cloudEnvironment -NotePropertyValue $Stored }

            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $TokenCloud)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.message | Should -BeLike "*$Remedy*"
            $script:Written.Count | Should -Be 0
            # ExecUpdateRefreshToken refused this sign-in, so the stored token is the working one.
            Should -Invoke Remove-CIPPDirectTenantToken -Times 0
        }

        It 'keeps an existing direct tenant''s stored token when the sign-in token cannot be classified' {
            $script:ExistingTenant = [pscustomobject]@{
                PartitionKey = 'Tenants'; RowKey = $script:TenantId; customerId = $script:TenantId
                displayName = 'Contoso Gov'; defaultDomainName = 'contoso.us'
                delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'USGovHigh'
            }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -AccessToken 'not-a-jwt')
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $script:Written.Count | Should -Be 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 0
        }

        It 'leaves a legacy row without a cloud value untouched on a commercial refresh' {
            $script:ExistingTenant = [pscustomobject]@{
                PartitionKey = 'Tenants'; RowKey = $script:TenantId; customerId = $script:TenantId
                displayName = 'Contoso'; defaultDomainName = 'contoso.com'; delegatedPrivilegeStatus = 'directTenant'
            }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $null)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
            $script:Written[0].PSObject.Properties.Name | Should -Not -Contain 'cloudEnvironment'
        }
    }

    # The commercial consent flow posts the Graph access token Entra returned for the delegated Graph
    # scopes. Graph tokens are v1 tokens (iss sts.windows.net) and their aud is either the Graph URI or
    # Graph's app id, depending on how the scope was named. Every shape must keep onboarding and
    # re-authenticating commercial tenants working exactly as before #2.
    Context 'commercial consent tokens in the shapes Entra issues' {
        BeforeEach {
            Mock Get-CIPPTenantCloudEnvironment { 'Commercial' }
            $script:CommercialShapes = @(
                @{ aud = 'https://graph.microsoft.com'; iss = "https://sts.windows.net/$($script:TenantId)/" }
                @{ aud = '00000003-0000-0000-c000-000000000000'; iss = "https://sts.windows.net/$($script:TenantId)/" }
                @{ aud = 'https://graph.microsoft.com/'; iss = "https://sts.windows.net/$($script:TenantId)/" }
                @{ aud = '00000003-0000-0000-c000-000000000000'; iss = "https://login.microsoftonline.com/$($script:TenantId)/v2.0" }
                @{ aud = 'https://graph.microsoft.com'; iss = "https://login.microsoftonline.com/$($script:TenantId)/v2.0" }
            )
        }

        It 'adds a new commercial tenant for every token shape, with or without cloudEnvironment' {
            foreach ($Shape in $script:CommercialShapes) {
                foreach ($Cloud in @('Commercial', $null)) {
                    $script:Written.Clear()
                    $Token = New-TestJwt @{ aud = $Shape.aud; iss = $Shape.iss; tid = $script:TenantId; scp = 'Directory.ReadWrite.All'; ver = '1.0' }
                    $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $Cloud -AccessToken $Token)
                    $Response.StatusCode | Should -Be ([HttpStatusCode]::OK) -Because "aud $($Shape.aud) iss $($Shape.iss) cloud '$Cloud'"
                    $script:Written[0].cloudEnvironment | Should -BeExactly 'Commercial'
                }
            }
            Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Uri -ne 'https://graph.microsoft.com/v1.0/$batch' }
            Should -Invoke Remove-CIPPDirectTenantToken -Times 0
            Should -Invoke Start-CIPPOrchestrator -Times ($script:CommercialShapes.Count * 2) -Exactly
        }

        It 'refreshes an existing commercial direct tenant (stored <Stored>) for every token shape' -TestCases @(
            @{ Stored = 'Commercial' }
            @{ Stored = $null }
        ) {
            param($Stored)
            foreach ($Shape in $script:CommercialShapes) {
                $script:Written.Clear()
                $script:ExistingTenant = [pscustomobject]@{
                    PartitionKey = 'Tenants'; RowKey = $script:TenantId; customerId = $script:TenantId
                    displayName = 'Contoso'; defaultDomainName = 'contoso.com'; delegatedPrivilegeStatus = 'directTenant'
                }
                if ($Stored) { $script:ExistingTenant | Add-Member -NotePropertyName cloudEnvironment -NotePropertyValue $Stored }
                $Token = New-TestJwt @{ aud = $Shape.aud; iss = $Shape.iss; tid = $script:TenantId }
                $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud $null -AccessToken $Token)
                $Response.StatusCode | Should -Be ([HttpStatusCode]::OK) -Because "aud $($Shape.aud) iss $($Shape.iss)"
                $script:Written.Count | Should -Be 1
            }
            Should -Invoke Remove-CIPPDirectTenantToken -Times 0
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
        }

        It 'never calls the commercial Graph host for a government selection, even when the token names no cloud' {
            # aud = Graph's app id and a v1 issuer say nothing about the cloud: the selection decides the
            # host, and a commercial token simply fails there (Graph validates it).
            Mock Get-CIPPTenantCloudEnvironment { 'USGovHigh' }
            $Token = New-TestJwt @{ aud = '00000003-0000-0000-c000-000000000000'; iss = 'https://sts.windows.net/x/'; tid = $script:TenantId }
            $null = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovHigh' -AccessToken $Token)
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://graph.microsoft.us/v1.0/$batch' }
            Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Uri -like '*graph.microsoft.com*' }
        }
    }

    Context 'blocked GDAP conversion' {
        It 'rejects the conversion without detecting or writing' {
            $script:ExistingTenant = [pscustomobject]@{
                PartitionKey = 'Tenants'; RowKey = $script:TenantId; customerId = $script:TenantId
                displayName = 'Contoso GDAP'; defaultDomainName = 'contoso.com'
                delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
            }

            $Response = Invoke-ExecAddTenant -Request (New-AddRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
            Should -Invoke Remove-CIPPDirectTenantToken -Times 1
            $script:Written.Count | Should -Be 0
        }
    }

    Context 'access' {
        It 'returns 403 for a tenant-restricted caller before any detection' {
            Mock Test-CIPPAccess { @($script:TenantId) }
            $Response = Invoke-ExecAddTenant -Request (New-AddRequest)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::Forbidden)
            Should -Invoke Get-CIPPTenantCloudEnvironment -Times 0
            Should -Invoke Invoke-RestMethod -Times 0
        }
    }
}

Describe 'Invoke-ExecAddTenant with the real detection helper' {
    BeforeAll {
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTenantCloudEnvironment.ps1')
    }

    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock Test-CIPPAccess { @('AllTenants') }
        Mock Get-CippTable { @{ Context = $tablename } }
        Mock Get-CIPPAuthentication {}
        Mock Get-CIPPAzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity { $script:Written.Add($Entity) }
        Mock Remove-CIPPDirectTenantToken {}
        Mock Write-LogMessage {}
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock Start-CIPPOrchestrator {}
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://*graph.microsoft.*/v1.0/$batch' } { New-GraphBatchResponse }
    }

    It 'stores USGovDoD for a DoD tenant' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://login.microsoftonline.com/*' } {
            [pscustomobject]@{ cloud_instance_name = 'microsoftonline.us'; tenant_region_scope = 'USGov'; tenant_region_sub_scope = 'DOD' }
        }
        $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovDoD')
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $script:Written[0].cloudEnvironment | Should -Be 'USGovDoD'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq "https://login.microsoftonline.com/$($script:TenantId)/v2.0/.well-known/openid-configuration" }
    }

    It 'stores USGovHigh from the onmicrosoft.us initial domain when discovery is unreachable' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://login.microsoftonline.com/*' } { throw 'timed out' }
        $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovHigh')
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $script:Written[0].cloudEnvironment | Should -Be 'USGovHigh'
    }

    It 'stores Commercial for a commercial tenant' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://graph.microsoft.com/*' } { New-GraphBatchResponse -InitialDomain 'contoso.onmicrosoft.com' }
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://login.microsoftonline.com/*' } {
            [pscustomobject]@{ cloud_instance_name = 'microsoftonline.com'; tenant_region_scope = 'NA' }
        }
        $null = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'Commercial')
        $script:Written[0].cloudEnvironment | Should -Be 'Commercial'
    }

    It 'rejects a GCC High sign-in for a tenant discovery reports as commercial' {
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://graph.microsoft.us/*' } { New-GraphBatchResponse -InitialDomain 'contoso.onmicrosoft.com' }
        Mock Invoke-RestMethod -ParameterFilter { $Uri -like 'https://login.microsoftonline.com/*' } {
            [pscustomobject]@{ cloud_instance_name = 'microsoftonline.com'; tenant_region_scope = 'NA' }
        }
        $Response = Invoke-ExecAddTenant -Request (New-AddRequest -Cloud 'USGovHigh')
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        $script:Written.Count | Should -Be 0
        Should -Invoke Remove-CIPPDirectTenantToken -Times 1
    }
}
