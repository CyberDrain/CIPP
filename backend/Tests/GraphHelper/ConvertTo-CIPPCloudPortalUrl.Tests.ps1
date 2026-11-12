# Portal links for a government tenant (redanthrax/CIPP#4): the host of a commercial admin portal link is replaced
# with the documented government host from portalHosts in Config/cloudFeatureSupport.json, or $null when there
# is none. Everything else, and every Commercial link, comes back unchanged.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudPortalUrl.ps1')
    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    $script:Links = @(
        'https://admin.cloud.microsoft?delegatedOrg=contoso.onmicrosoft.com'
        'https://entra.microsoft.com/contoso.com/#view/X'
        'https://portal.azure.com/contoso.com'
        'https://intune.microsoft.com/contoso.com/'
        'https://security.microsoft.com/?tid=c1'
        'https://admin.teams.microsoft.com?delegatedOrg=contoso.com'
        'https://partner.microsoft.com/dashboard/v2/customers/c1/servicemanagementpage'
        '/api/ListSharePointAdminUrl?tenantFilter=contoso.com'
    )
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'ConvertTo-CIPPCloudPortalUrl' {
    BeforeEach { $script:CIPPCloudPortalHosts = $null }

    It 'returns every link unchanged for cloud <Name>, without reading the map' -TestCases @(
        @{ Name = 'Commercial'; Cloud = 'Commercial' }
        @{ Name = 'none'; Cloud = '' }
    ) {
        param($Name, $Cloud)
        foreach ($Url in $script:Links) { ConvertTo-CIPPCloudPortalUrl -Url $Url -CloudEnvironment $Cloud | Should -BeExactly $Url }
        $script:CIPPCloudPortalHosts | Should -BeNullOrEmpty
    }

    It 'maps documented portals for <Cloud>' -TestCases @(
        @{ Cloud = 'USGovHigh'; Security = 'https://security.microsoft.us/?tid=c1'; Purview = 'https://purview.microsoft.us/?tid=c1' }
        @{ Cloud = 'USGovDoD'; Security = 'https://security.apps.mil/?tid=c1'; Purview = 'https://purview.apps.mil/?tid=c1' }
    ) {
        param($Cloud, $Security, $Purview)
        ConvertTo-CIPPCloudPortalUrl -Url 'https://purview.microsoft.com/?tid=c1' -CloudEnvironment $Cloud | Should -BeExactly $Purview
        ConvertTo-CIPPCloudPortalUrl -Url 'https://entra.microsoft.com/contoso.com/#view/X' -CloudEnvironment $Cloud | Should -BeExactly 'https://entra.microsoft.us/contoso.com/#view/X'
        ConvertTo-CIPPCloudPortalUrl -Url 'https://portal.azure.com/contoso.com' -CloudEnvironment $Cloud | Should -BeExactly 'https://portal.azure.us/contoso.com'
        ConvertTo-CIPPCloudPortalUrl -Url 'https://aad.portal.azure.com/contoso.com/#blade/X' -CloudEnvironment $Cloud | Should -BeExactly 'https://portal.azure.us/contoso.com/#blade/X'
        ConvertTo-CIPPCloudPortalUrl -Url 'https://endpoint.microsoft.com/contoso.com/' -CloudEnvironment $Cloud | Should -BeExactly 'https://intune.microsoft.us/contoso.com/'
        ConvertTo-CIPPCloudPortalUrl -Url 'https://security.microsoft.com/?tid=c1' -CloudEnvironment $Cloud | Should -BeExactly $Security
    }

    It 'returns $null for portals without a documented government URL' {
        foreach ($Url in 'https://admin.cloud.microsoft?delegatedOrg=x', 'https://admin.microsoft.com/Partner/BeginClientSession.aspx?CTID=c1', 'https://portal.office.com/Partner/BeginClientSession.aspx?CTID=c1',
            'https://admin.teams.microsoft.com?delegatedOrg=x', 'https://compliance.microsoft.com/', 'https://app.powerbi.com/admin-portal?ctid=c1') {
            ConvertTo-CIPPCloudPortalUrl -Url $Url -CloudEnvironment 'USGovHigh' | Should -BeNullOrEmpty -Because $Url
        }
    }

    It 'leaves other hosts, relative links and non-strings alone for a government tenant' {
        ConvertTo-CIPPCloudPortalUrl -Url $script:Links[6] -CloudEnvironment 'USGovHigh' | Should -BeExactly $script:Links[6]
        ConvertTo-CIPPCloudPortalUrl -Url $script:Links[7] -CloudEnvironment 'USGovHigh' | Should -BeExactly $script:Links[7]
        ConvertTo-CIPPCloudPortalUrl -Url 'https://entra.microsoft.com.example.org/x' -CloudEnvironment 'USGovHigh' | Should -BeExactly 'https://entra.microsoft.com.example.org/x'
        ConvertTo-CIPPCloudPortalUrl -Url $null -CloudEnvironment 'USGovHigh' | Should -BeNullOrEmpty
    }

    It 'leaves links unchanged when the map cannot be read' {
        $env:CIPPRootPath = Join-Path $TestDrive 'missing'
        try {
            ConvertTo-CIPPCloudPortalUrl -Url 'https://entra.microsoft.com/x' -CloudEnvironment 'USGovHigh' | Should -BeExactly 'https://entra.microsoft.com/x'
        } finally { $env:CIPPRootPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) }
    }
}
