# Request routing by cloud (redanthrax/CIPP#3). Pinned invariants, from the #1 security review:
#   - hosts come only from the literal map in Get-CIPPCloudEndpoint; unknown, empty or miscased
#     clouds throw before any request
#   - a commercial tenant's URIs are passed through byte for byte
#   - a government tenant's requests never reach a commercial host: Graph, Exchange, Management and
#     Defender move to the tenant's cloud, anything without a documented government host throws
#   - only the host is rewritten ([uri]-parsed, exact host match), never a substring
# No test makes a network call: Invoke-CIPPRestMethod and Get-GraphToken are mocked throughout.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CIPPTokenCache' -as [type])) {
        Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    }

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-AuthorisedRequestError { param($TenantID, $Context) }
    function Get-GraphToken { param($tenantid, $scope, $AsApp, $SkipCache, [switch]$UseCertificate, [string]$RequireCloud) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $ContentType, $Body, $ResponseHeadersVariable, $StatusCodeVariable, [switch]$SkipHttpErrorCheck, $MaximumRedirection, $TimeoutSec) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CippUserAgent { param([switch]$SharePoint) 'CIPP-test' }
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) [pscustomobject]@{ customerId = $script:GovTenant; defaultDomainName = 'gov.example'; initialDomainName = 'gov.onmicrosoft.us' } }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $tenantid, $message, $Sev, $LogData, $headers) }
    function Get-CIPPSAMCertificate { param($Name, [switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) }

    foreach ($File in 'Get-CIPPCloudEndpoint', 'Resolve-CIPPCloudHost', 'ConvertTo-CIPPCloudUri', 'ConvertTo-CIPPCloudScope',
        'Get-CIPPPartnerCloudEnvironment', 'Get-CIPPTenantRequestCloud', 'New-GraphGetRequest', 'New-GraphPOSTRequest',
        'New-GraphBulkRequest', 'New-GraphMultiTenantBulkRequest', 'New-ExoRequest', 'New-ExoBulkRequest', 'New-TeamsRequestV2',
        'Get-ClassicAPIToken', 'New-CIPPMFAConnectorToken') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/GraphHelper/$File.ps1")
    }

    $script:Partner = '11111111-2222-3333-4444-555555555555'
    $script:GovTenant = 'a0000000-0000-0000-0000-00000000000a'
    $script:ComTenant = 'c0000000-0000-0000-0000-00000000000c'
    $script:Clouds = @{
        Commercial = @{ Graph = 'graph.microsoft.com'; Exchange = 'outlook.office365.com' }
        USGovHigh  = @{ Graph = 'graph.microsoft.us'; Exchange = 'outlook.office365.us' }
        USGovDoD   = @{ Graph = 'dod-graph.microsoft.us'; Exchange = 'webmail.apps.mil' }
    }
    # Any of these in a request for a government tenant is a leak.
    $script:CommercialHost = '^https://(graph\.microsoft\.com|outlook\.office365\.com|manage\.office\.com|api\.securitycenter\.(microsoft|windows)\.com|[^/]*\.teams\.microsoft\.com|[^/]*\.protection\.outlook\.com|login\.microsoftonline\.com)(/|:|\?|$)'
}

Describe 'Resolve-CIPPCloudHost' {
    It 'returns every host unchanged for Commercial: <HostName>' -TestCases @(
        @{ HostName = 'graph.microsoft.com' }
        @{ HostName = 'api.partnercenter.microsoft.com' }
        @{ HostName = 'contoso.sharepoint.com' }
        @{ HostName = 'GRAPH.MICROSOFT.COM' }
    ) {
        param($HostName)
        Resolve-CIPPCloudHost -HostName $HostName -CloudEnvironment 'Commercial' | Should -BeExactly $HostName
    }

    It 'maps <HostName> to <Expected> for <Cloud>' -TestCases @(
        @{ Cloud = 'USGovHigh'; HostName = 'graph.microsoft.com'; Expected = 'graph.microsoft.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'graph.microsoft.com'; Expected = 'dod-graph.microsoft.us' }
        @{ Cloud = 'USGovHigh'; HostName = 'Graph.Microsoft.COM'; Expected = 'graph.microsoft.us' }
        @{ Cloud = 'USGovHigh'; HostName = 'outlook.office365.com'; Expected = 'outlook.office365.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'outlook.office365.com'; Expected = 'webmail.apps.mil' }
        @{ Cloud = 'USGovHigh'; HostName = 'manage.office.com'; Expected = 'manage.office365.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'manage.office.com'; Expected = 'manage.protection.apps.mil' }
        @{ Cloud = 'USGovHigh'; HostName = 'api.securitycenter.microsoft.com'; Expected = 'api-gov.securitycenter.microsoft.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'api.securitycenter.windows.com'; Expected = 'api-gov.securitycenter.microsoft.us' }
        @{ Cloud = 'USGovHigh'; HostName = 'graph.microsoft.us'; Expected = 'graph.microsoft.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'webmail.apps.mil'; Expected = 'webmail.apps.mil' }
        @{ Cloud = 'USGovHigh'; HostName = 'contoso-admin.sharepoint.us'; Expected = 'contoso-admin.sharepoint.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'contoso.sharepoint-mil.us'; Expected = 'contoso.sharepoint-mil.us' }
    ) {
        param($Cloud, $HostName, $Expected)
        Resolve-CIPPCloudHost -HostName $HostName -CloudEnvironment $Cloud | Should -BeExactly $Expected
    }

    It 'refuses <HostName> for <Cloud>' -TestCases @(
        @{ Cloud = 'USGovHigh'; HostName = 'api.partnercenter.microsoft.com' }
        @{ Cloud = 'USGovHigh'; HostName = 'api.interfaces.records.teams.microsoft.com' }
        @{ Cloud = 'USGovHigh'; HostName = 'ps.compliance.protection.outlook.com' }
        @{ Cloud = 'USGovHigh'; HostName = 'admin.microsoft.com' }
        @{ Cloud = 'USGovHigh'; HostName = 'reports.office.com' }
        @{ Cloud = 'USGovHigh'; HostName = 'contoso.sharepoint.com' }
        @{ Cloud = 'USGovHigh'; HostName = 'sharepoint.us' }
        @{ Cloud = 'USGovHigh'; HostName = 'contoso.sharepoint-mil.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'contoso.sharepoint.us' }
        @{ Cloud = 'USGovDoD'; HostName = 'graph.microsoft.us' }
        @{ Cloud = 'USGovHigh'; HostName = 'dod-graph.microsoft.us' }
        @{ Cloud = 'USGovHigh'; HostName = 'graph.microsoft.com.evil.example' }
        @{ Cloud = 'USGovHigh'; HostName = 'evilgraph.microsoft.com' }
        @{ Cloud = 'USGovHigh'; HostName = '' }
    ) {
        param($Cloud, $HostName)
        { Resolve-CIPPCloudHost -HostName $HostName -CloudEnvironment $Cloud } | Should -Throw '*not supported for government tenants*'
    }

    It 'throws for an unknown, empty or miscased cloud: <Value>' -TestCases @(
        @{ Value = '' }
        @{ Value = $null }
        @{ Value = 'usgovhigh' }
        @{ Value = 'USGOVDOD' }
        @{ Value = 'GCCHigh' }
    ) {
        param($Value)
        { Resolve-CIPPCloudHost -HostName 'graph.microsoft.com' -CloudEnvironment $Value } | Should -Throw '*Unknown cloud environment*'
    }
}

Describe 'ConvertTo-CIPPCloudUri' {
    It 'returns a commercial URI byte for byte: <Uri>' -TestCases @(
        @{ Uri = 'https://graph.microsoft.com/beta/users?$top=999&$filter=startswith(displayName,''A'')' }
        @{ Uri = 'https://GRAPH.microsoft.com:443/v1.0/me/sendMail' }
        @{ Uri = 'https://outlook.office365.com/adminapi/beta/x/Mailbox?$filter=RecipientTypeDetails%20eq%20''SharedMailbox''' }
        @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers' }
        @{ Uri = 'not a uri' }
        @{ Uri = '' }
    ) {
        param($Uri)
        ConvertTo-CIPPCloudUri -Uri $Uri -CloudEnvironment 'Commercial' | Should -BeExactly $Uri
    }

    It 'moves a Graph URI to the <Cloud> host and keeps the rest byte for byte' -TestCases @(
        @{ Cloud = 'USGovHigh'; ApiHost = 'graph.microsoft.us' }
        @{ Cloud = 'USGovDoD'; ApiHost = 'dod-graph.microsoft.us' }
    ) {
        param($Cloud, $ApiHost)
        $Rest = '/beta/users?$filter=mail%20eq%20''a@graph.microsoft.com''&$select=id,displayName#frag'
        ConvertTo-CIPPCloudUri -Uri "https://graph.microsoft.com$Rest" -CloudEnvironment $Cloud | Should -BeExactly "https://$ApiHost$Rest"
    }

    It 'rewrites only the host, not the same text elsewhere in the URI' {
        $Result = ConvertTo-CIPPCloudUri -Uri 'https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.us:/sites/graph.microsoft.com' -CloudEnvironment 'USGovHigh'
        $Result | Should -BeExactly 'https://graph.microsoft.us/v1.0/sites/contoso.sharepoint.us:/sites/graph.microsoft.com'
    }

    It 'handles an upper-case host and an explicit :443' {
        ConvertTo-CIPPCloudUri -Uri 'https://GRAPH.MICROSOFT.COM:443/beta/users' -CloudEnvironment 'USGovHigh' | Should -BeExactly 'https://graph.microsoft.us/beta/users'
        ConvertTo-CIPPCloudUri -Uri 'https://outlook.office365.com:443/adminapi/beta/t/mailbox' -CloudEnvironment 'USGovDoD' | Should -BeExactly 'https://webmail.apps.mil/adminapi/beta/t/mailbox'
    }

    It 'routes a bare host (an Exchange resource) for <Cloud>' -TestCases @(
        @{ Cloud = 'USGovHigh'; Expected = 'https://outlook.office365.us' }
        @{ Cloud = 'USGovDoD'; Expected = 'https://webmail.apps.mil' }
    ) {
        param($Cloud, $Expected)
        ConvertTo-CIPPCloudUri -Uri 'https://outlook.office365.com' -CloudEnvironment $Cloud | Should -BeExactly $Expected
    }

    It 'keeps a nextLink that is already on the tenant''s cloud' {
        $Next = 'https://dod-graph.microsoft.us/beta/users?$skiptoken=abc'
        ConvertTo-CIPPCloudUri -Uri $Next -CloudEnvironment 'USGovDoD' | Should -BeExactly $Next
    }

    It 'refuses <Name> for a government tenant' -TestCases @(
        @{ Name = 'a look-alike host'; Uri = 'https://graph.microsoft.com.evil.example/beta/users' }
        @{ Name = 'the commercial host in the path only'; Uri = 'https://evil.example/graph.microsoft.com/beta' }
        @{ Name = 'user info'; Uri = 'https://user@graph.microsoft.com/beta/users' }
        @{ Name = 'a backslash authority'; Uri = 'https://graph.microsoft.com\@evil.example/beta' }
        @{ Name = 'another port'; Uri = 'https://graph.microsoft.com:8443/beta/users' }
        @{ Name = 'http'; Uri = 'http://graph.microsoft.com/beta/users' }
        @{ Name = 'a relative URI'; Uri = '/beta/users' }
        @{ Name = 'an empty URI'; Uri = '' }
        @{ Name = 'a host with no government equivalent'; Uri = 'https://api.partnercenter.microsoft.com/v1/customers' }
        @{ Name = 'another government cloud''s nextLink'; Uri = 'https://graph.microsoft.us/beta/users?$skiptoken=abc' }
    ) {
        param($Name, $Uri)
        { ConvertTo-CIPPCloudUri -Uri $Uri -CloudEnvironment 'USGovDoD' } | Should -Throw
    }

    It 'throws for an unknown cloud' {
        { ConvertTo-CIPPCloudUri -Uri 'https://graph.microsoft.com/beta/users' -CloudEnvironment 'usgovhigh' } | Should -Throw '*Unknown cloud environment*'
    }
}

Describe 'Get-CIPPTenantRequestCloud' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        $script:SavedTenantID = $env:TenantID
        $script:SavedPartnerCloud = $env:CIPP_PARTNER_CLOUD
        $env:TenantID = $script:Partner
        Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue
        $script:GovCloud = 'USGovHigh'
        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ customerId = $script:GovTenant; defaultDomainName = 'gov.example'; initialDomainName = 'gov.onmicrosoft.us'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = $script:GovCloud }
                [pscustomobject]@{ customerId = $script:ComTenant; defaultDomainName = 'com.example'; initialDomainName = 'com.onmicrosoft.com'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'Commercial' }
            )
        }
    }
    AfterEach {
        $env:TenantID = $script:SavedTenantID
        if ($null -eq $script:SavedPartnerCloud) { Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue } else { $env:CIPP_PARTNER_CLOUD = $script:SavedPartnerCloud }
    }

    It 'reads a direct tenant''s stored cloud once, then answers from the marker (<Cloud>)' -TestCases @(
        @{ Cloud = 'USGovHigh' }
        @{ Cloud = 'USGovDoD' }
    ) {
        param($Cloud)
        $script:GovCloud = $Cloud
        Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly $Cloud
        Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly $Cloud
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
        [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 0).TokenPayloadJson | Should -BeExactly $Cloud
    }

    It 'finds a direct tenant by its default domain' {
        Get-CIPPTenantRequestCloud -TenantFilter 'gov.example' | Should -BeExactly 'USGovHigh'
    }

    It 'finds a government direct tenant by its initial domain (redanthrax/CIPP#2, #3)' {
        Get-CIPPTenantRequestCloud -TenantFilter 'gov.onmicrosoft.us' | Should -BeExactly 'USGovHigh'
    }

    It 'does not match a commercial direct tenant by its initial domain: the partner cloud, as before' {
        Get-CIPPTenantRequestCloud -TenantFilter 'com.onmicrosoft.com' | Should -BeExactly 'Commercial'
        $null = [CIPP.CIPPTokenCache]::Clear()
        $env:CIPP_PARTNER_CLOUD = 'USGovHigh'
        try {
            # Only visible when the partner cloud differs: the commercial row's initial domain is not used.
            Get-CIPPTenantRequestCloud -TenantFilter 'com.onmicrosoft.com' | Should -BeExactly 'USGovHigh'
        } finally { Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue }
    }

    It 'resolves a padded tenant id like the tenant and never overwrites its marker with the partner cloud: <Name>' -TestCases @(
        @{ Name = 'space'; Pad = ' ' }
        @{ Name = 'tab'; Pad = "`t" }
        @{ Name = 'no-break space'; Pad = [string][char]0xA0 }
    ) {
        param($Name, $Pad)
        # CIPPTokenCache.BuildKey trims, so the padded id shares the tenant's marker key.
        Get-CIPPTenantRequestCloud -TenantFilter "$Pad$($script:GovTenant)$Pad" | Should -BeExactly 'USGovHigh'
        [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 0).TokenPayloadJson | Should -BeExactly 'USGovHigh'
        Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly 'USGovHigh'
    }

    It 'uses the marker Get-GraphToken left, with no table read' {
        [CIPP.CIPPTokenCache]::Store([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 'USGovDoD', [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
        Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant | Should -BeExactly 'USGovDoD'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'answers Commercial for a commercial direct tenant, a GDAP tenant and the partner tenant' {
        Get-CIPPTenantRequestCloud -TenantFilter $script:ComTenant | Should -BeExactly 'Commercial'
        Get-CIPPTenantRequestCloud -TenantFilter 'gdap.example' | Should -BeExactly 'Commercial'
        Get-CIPPTenantRequestCloud -TenantFilter $script:Partner | Should -BeExactly 'Commercial'
        Get-CIPPTenantRequestCloud -TenantFilter '' | Should -BeExactly 'Commercial'
    }

    It 'does not read the table for the partner tenant' {
        $null = Get-CIPPTenantRequestCloud -TenantFilter $script:Partner
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'follows the partner cloud for tenants without a stored cloud' {
        $env:CIPP_PARTNER_CLOUD = 'USGovHigh'
        Get-CIPPTenantRequestCloud -TenantFilter 'gdap.example' | Should -BeExactly 'USGovHigh'
    }

    It 'fails closed for a stored cloud of <Value>' -TestCases @(
        @{ Value = 'usgovhigh' }
        @{ Value = 'GCCHigh' }
        @{ Value = 'USGovHigh ' }
    ) {
        param($Value)
        $script:GovCloud = $Value
        { Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant } | Should -Throw '*Unknown cloud environment*'
        [CIPP.CIPPTokenCache]::Lookup([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 0).Found | Should -BeFalse
    }

    It 'fails closed for a bad marker' {
        [CIPP.CIPPTokenCache]::Store([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 'usgovdod', [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
        { Get-CIPPTenantRequestCloud -TenantFilter $script:GovTenant } | Should -Throw '*Unknown cloud environment*'
    }

    It 'fails closed for a bad CIPP_PARTNER_CLOUD' {
        $env:CIPP_PARTNER_CLOUD = 'usgovhigh'
        { Get-CIPPTenantRequestCloud -TenantFilter 'gdap.example' } | Should -Throw '*CIPP_PARTNER_CLOUD*'
    }
}

Describe 'Request helpers' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        $script:SavedTenantID = $env:TenantID
        $script:SavedPartnerCloud = $env:CIPP_PARTNER_CLOUD
        $env:TenantID = $script:Partner
        Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue
        $script:GovCloud = 'USGovHigh'
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Bodies = [System.Collections.Generic.List[string]]::new()
        $script:Replies = [System.Collections.Generic.Queue[object]]::new()
        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*directTenant*') {
                return @(
                    [pscustomobject]@{ customerId = $script:GovTenant; defaultDomainName = 'gov.example'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = $script:GovCloud }
                    [pscustomobject]@{ customerId = $script:ComTenant; defaultDomainName = 'com.example'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'Commercial' }
                )
            }
        }
        Mock Get-GraphToken { @{ Authorization = 'Bearer test' } }
        Mock Start-Sleep {}
        Mock Invoke-CIPPRestMethod {
            $script:Calls.Add([string]$Uri)
            if ($Body -is [string]) { $script:Bodies.Add($Body) }
            if ($script:Replies.Count -gt 0) { return $script:Replies.Dequeue() }
            [pscustomobject]@{ value = @([pscustomobject]@{ id = '1' }) }
        }
    }
    AfterEach {
        $env:TenantID = $script:SavedTenantID
        if ($null -eq $script:SavedPartnerCloud) { Remove-Item env:CIPP_PARTNER_CLOUD -ErrorAction SilentlyContinue } else { $env:CIPP_PARTNER_CLOUD = $script:SavedPartnerCloud }
    }

    Context 'New-GraphGetRequest' {
        It 'sends a commercial tenant''s URI exactly as given' {
            $Uri = 'https://graph.microsoft.com/beta/users?$top=999&$filter=startswith(displayName,''A'')'
            $null = New-GraphGetRequest -uri $Uri -tenantid $script:ComTenant
            $script:Calls | Should -Be @($Uri)
        }

        It 'sends a <Cloud> tenant''s Graph request to <ApiHost> and never to a commercial host' -TestCases @(
            @{ Cloud = 'USGovHigh'; ApiHost = 'graph.microsoft.us' }
            @{ Cloud = 'USGovDoD'; ApiHost = 'dod-graph.microsoft.us' }
        ) {
            param($Cloud, $ApiHost)
            $script:GovCloud = $Cloud
            $null = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$select=id' -tenantid $script:GovTenant
            $script:Calls | Should -Be @("https://$ApiHost/v1.0/users?`$select=id")
            @($script:Calls | Where-Object { $_ -match $script:CommercialHost }).Count | Should -Be 0
        }

        It 'routes the Exchange REST URIs callers send through it (scope ExchangeOnline)' {
            $null = New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($script:GovTenant)/Mailbox" -tenantid $script:GovTenant -scope 'ExchangeOnline'
            $script:Calls | Should -Be @("https://outlook.office365.us/adminapi/beta/$($script:GovTenant)/Mailbox")
            Should -Invoke Get-GraphToken -ParameterFilter { $scope -eq 'https://outlook.office365.com/.default' }
        }

        It 'follows a government nextLink unchanged' {
            $Next = 'https://graph.microsoft.us/v1.0/users?$skiptoken=page2'
            $script:Replies.Enqueue([pscustomobject]@{ value = @([pscustomobject]@{ id = '1' }); '@odata.nextLink' = $Next })
            $script:Replies.Enqueue([pscustomobject]@{ value = @([pscustomobject]@{ id = '2' }) })
            $Result = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:GovTenant
            @($Result).id | Should -Be @('1', '2')
            $script:Calls | Should -Be @('https://graph.microsoft.us/v1.0/users', $Next)
        }

        It 'refuses a nextLink that leaves the tenant''s cloud, without calling it' {
            $script:Replies.Enqueue([pscustomobject]@{ value = @(); '@odata.nextLink' = 'https://evil.example/v1.0/users?$skiptoken=page2' })
            { New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:GovTenant } | Should -Throw '*not supported for government tenants*'
            $script:Calls | Should -Be @('https://graph.microsoft.us/v1.0/users')
        }

        It 'refuses a host with no government equivalent, without a request' {
            { New-GraphGetRequest -uri 'https://reports.office.com/odataux/x' -tenantid $script:GovTenant -scope 'https://reports.office.com/.default' } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'fails closed for an unknown stored cloud, with no request: <Value>' -TestCases @(
            @{ Value = 'usgovhigh' }
            @{ Value = 'USGov' }
        ) {
            param($Value)
            $script:GovCloud = $Value
            { New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:GovTenant } | Should -Throw '*Unknown cloud environment*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'routes a request made with caller-supplied headers too' {
            $null = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization' -tenantid $script:GovTenant -NoAuthCheck $true -Headers @{ Authorization = 'Bearer x' }
            $script:Calls | Should -Be @('https://graph.microsoft.us/v1.0/organization')
        }
    }

    Context 'New-GraphPOSTRequest' {
        It 'sends a commercial tenant''s URI exactly as given' {
            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $script:ComTenant -body '{}'
            $script:Calls | Should -Be @('https://graph.microsoft.com/beta/users')
        }

        It 'sends a <Cloud> tenant''s request to <ApiHost>' -TestCases @(
            @{ Cloud = 'USGovHigh'; ApiHost = 'graph.microsoft.us' }
            @{ Cloud = 'USGovDoD'; ApiHost = 'dod-graph.microsoft.us' }
        ) {
            param($Cloud, $ApiHost)
            $script:GovCloud = $Cloud
            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users/x' -tenantid $script:GovTenant -type PATCH -body '{}'
            $script:Calls | Should -Be @("https://$ApiHost/beta/users/x")
        }

        It 'fails closed for an unknown stored cloud, with no request' {
            $script:GovCloud = 'Commercial '
            { New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $script:GovTenant -body '{}' } | Should -Throw '*Unknown cloud environment*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }
    }

    Context 'New-GraphBulkRequest' {
        BeforeEach {
            $script:Requests = @(@{ id = 'u'; method = 'GET'; url = '/users?$top=999' })
        }

        It 'posts a commercial tenant''s batch to the commercial host' {
            $null = New-GraphBulkRequest -tenantid $script:ComTenant -Requests $script:Requests
            $script:Calls | Should -Be @('https://graph.microsoft.com/beta/$batch')
        }

        It 'posts a <Cloud> tenant''s batch to <ApiHost> and re-batches its nextLink as a relative URL' -TestCases @(
            @{ Cloud = 'USGovHigh'; ApiHost = 'graph.microsoft.us' }
            @{ Cloud = 'USGovDoD'; ApiHost = 'dod-graph.microsoft.us' }
        ) {
            param($Cloud, $ApiHost)
            $script:GovCloud = $Cloud
            $Page1 = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'a' }); '@odata.nextLink' = "https://$ApiHost/beta/users?`$top=999&`$skiptoken=p2" }
            $script:Replies.Enqueue([pscustomobject]@{ responses = @([pscustomobject]@{ id = 'u'; status = 200; body = $Page1 }) })
            $script:Replies.Enqueue([pscustomobject]@{ responses = @([pscustomobject]@{ id = 'u'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'b' }) } }) })

            $Result = @(New-GraphBulkRequest -tenantid $script:GovTenant -Requests $script:Requests -Version 'beta')

            @($Result[0].body.value).id | Should -Be @('a', 'b')
            $script:Calls | Should -Be @("https://$ApiHost/beta/`$batch", "https://$ApiHost/beta/`$batch")
            ($script:Bodies[1] | ConvertFrom-Json).requests[0].url | Should -BeExactly '/users?$top=999&$skiptoken=p2'
        }

        It 'fails closed for an unknown stored cloud, with no request' {
            $script:GovCloud = 'dod'
            { New-GraphBulkRequest -tenantid $script:GovTenant -Requests $script:Requests } | Should -Throw '*Unknown cloud environment*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }
    }

    Context 'New-GraphMultiTenantBulkRequest' {
        It 'reports an unknown cloud as that tenant''s error and sends nothing for it' {
            $script:GovCloud = 'usgovhigh'
            $Result = New-GraphMultiTenantBulkRequest -TenantRequests @(@{ TenantFilter = $script:GovTenant; Requests = @(@{ id = '1'; method = 'GET'; url = '/users' }) })
            $Result[0].Error | Should -BeLike '*Unknown cloud environment*'
        }
    }

    Context 'New-ExoRequest and New-ExoBulkRequest' {
        It 'calls the <Cloud> Exchange host <ApiHost>' -TestCases @(
            @{ Cloud = 'USGovHigh'; ApiHost = 'outlook.office365.us' }
            @{ Cloud = 'USGovDoD'; ApiHost = 'webmail.apps.mil' }
        ) {
            param($Cloud, $ApiHost)
            $script:GovCloud = $Cloud
            $null = New-ExoRequest -tenantid $script:GovTenant -cmdlet 'Get-Mailbox'
            $script:Calls | Should -Be @("https://$ApiHost/adminapi/beta/$($script:GovTenant)/InvokeCommand")
        }

        It 'keeps a government tenant''s Exchange nextLink on its own cloud (<Name>)' -TestCases @(
            @{ Name = 'commercial host'; Next = 'https://outlook.office365.com/adminapi/beta/x/InvokeCommand?$skiptoken=2'; Expected = 'https://outlook.office365.us/adminapi/beta/x/InvokeCommand?$skiptoken=2' }
            @{ Name = 'own host'; Next = 'https://outlook.office365.us/adminapi/beta/x/InvokeCommand?$skiptoken=2'; Expected = 'https://outlook.office365.us/adminapi/beta/x/InvokeCommand?$skiptoken=2' }
        ) {
            param($Name, $Next, $Expected)
            $script:Replies.Enqueue([pscustomobject]@{ value = @([pscustomobject]@{ Name = 'a' }); '@odata.nextLink' = $Next })
            $script:Replies.Enqueue([pscustomobject]@{ value = @([pscustomobject]@{ Name = 'b' }) })
            $null = New-ExoRequest -tenantid $script:GovTenant -cmdlet 'Get-Mailbox'
            $script:Calls | Should -Be @("https://outlook.office365.us/adminapi/beta/$($script:GovTenant)/InvokeCommand", $Expected)
        }

        It 'refuses an Exchange nextLink that leaves the tenant''s cloud, without calling it (<Name>)' -TestCases @(
            @{ Name = 'paged'; Stream = $false }
            @{ Name = 'streamed'; Stream = $true }
        ) {
            param($Name, $Stream)
            $script:Replies.Enqueue([pscustomobject]@{ value = @(); '@odata.nextLink' = 'https://evil.example/adminapi/beta/x/InvokeCommand' })
            { $null = New-ExoRequest -tenantid $script:GovTenant -cmdlet 'Get-Mailbox' -StreamPages:$Stream } | Should -Throw '*not supported for government tenants*'
            $script:Calls | Should -Be @("https://outlook.office365.us/adminapi/beta/$($script:GovTenant)/InvokeCommand")
        }

        It 'keeps the commercial Exchange host for a commercial tenant' {
            $null = New-ExoRequest -tenantid $script:ComTenant -cmdlet 'Get-Mailbox'
            $script:Calls | Should -Be @("https://outlook.office365.com/adminapi/beta/$($script:GovTenant)/InvokeCommand")
        }

        It 'refuses Security & Compliance for a government tenant, with no request' {
            { New-ExoRequest -tenantid $script:GovTenant -cmdlet 'Get-Label' -Compliance } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'posts a government tenant''s Exchange batch to its own host' {
            $script:Replies.Enqueue([pscustomobject]@{ responses = @() })
            $null = New-ExoBulkRequest -tenantid $script:GovTenant -cmdletArray @(@{ CmdletInput = @{ CmdletName = 'Get-Mailbox'; Parameters = @{} } })
            $script:Calls | Should -Be @("https://outlook.office365.us/adminapi/beta/$($script:GovTenant)/`$batch")
        }
    }

    Context 'Services with no government host' {
        It 'New-TeamsRequestV2 refuses a government tenant before asking for a token' {
            { New-TeamsRequestV2 -TenantFilter $script:GovTenant -Type 'TeamsMeetingPolicy' } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Get-GraphToken -Times 0
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'Get-ClassicAPIToken refuses a government tenant before the commercial token endpoint' {
            { Get-ClassicAPIToken -tenantID $script:GovTenant -Resource 'https://admin.microsoft.com' } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
        }

        It 'New-CIPPMFAConnectorToken checks again before sending a secret when this worker''s marker was stale' {
            # A stale 'Commercial' marker (e.g. a cloud change made in another worker) passes the first check;
            # Get-GraphToken's table read then refreshes it, as its slow path does.
            $script:MarkerKey = [CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker')
            [CIPP.CIPPTokenCache]::Store($script:MarkerKey, 'Commercial', [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
            Mock Get-GraphToken { [CIPP.CIPPTokenCache]::Store($script:MarkerKey, 'USGovHigh', [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900); @{ Authorization = 'Bearer test' } }
            Mock Invoke-RestMethod {}
            $script:Replies.Enqueue([pscustomobject]@{ value = @([pscustomobject]@{ id = 'sp-1'; passwordCredentials = @() }) })
            $script:Replies.Enqueue([pscustomobject]@{ secretText = 'new-secret' })
            { New-CIPPMFAConnectorToken -TenantFilter $script:GovTenant -ForceProvision } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-RestMethod -Times 0
            $script:Calls | Should -Not -Match 'graph\.microsoft\.com'
        }

        It 'New-CIPPMFAConnectorToken refuses a government tenant before provisioning or sending a secret' {
            { New-CIPPMFAConnectorToken -TenantFilter $script:GovTenant } | Should -Throw '*not supported for government tenants*'
            Should -Invoke Invoke-CIPPRestMethod -Times 0
            Should -Invoke Get-GraphToken -Times 0
        }
    }
}
