# Pester tests for Get-CIPPSharePointSiteUsageRows: the requests it sends, the document library lookup and the site archive state.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointSiteUsageRows.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-SPOUsageRootWebTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSharePointSiteUsagePayload.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPSPOAdminListViewXml.ps1')

    $script:SiteIds = @(0..2 | ForEach-Object { '00000000-0000-0000-0000-{0:d12}' -f $_ })

    function Get-Tenants { param($TenantFilter) [pscustomobject]@{ customerId = 'tenant-guid' } }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) [pscustomobject]@{ AdminUrl = 'https://contoso-admin.sharepoint.com' } }
    function Write-LogMessage { param($Message, $Sev, $tenant, $API, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-CIPPSPOAdminListData {
        param($TenantFilter, $AdminUrl, $Type, $RowLimit, $ViewFields)
        $script:AdminCall = @{ RowLimit = $RowLimit; ViewFields = $ViewFields }
        foreach ($Id in $script:SiteIds) {
            $Row = [pscustomobject]@{ SiteId = "{$Id}"; SiteUrl = "https://contoso.sharepoint.com/sites/$Id"; Title = $Id; TemplateName = 'GROUP#0'; StorageUsed = 1 }
            if ($null -ne $script:ArchiveStatus) { $Row | Add-Member -NotePropertyName 'ArchiveStatus' -NotePropertyValue $script:ArchiveStatus }
            $Row
        }
    }
    function New-GraphBulkRequest {
        param($tenantid, $Requests, $asapp, $scope)
        $Requests = @($Requests)
        $script:BulkUrls.AddRange([string[]]@($Requests.url))
        if ($Requests[0].url -like 'sites/getAllSites*') {
            $Sites = foreach ($Id in $script:SiteIds) {
                [pscustomobject]@{ id = "contoso.sharepoint.com,$Id,web-$Id"; webUrl = "https://contoso.sharepoint.com/sites/$Id"; sharepointIds = [pscustomobject]@{ siteId = $Id; webId = "web-$Id" } }
            }
            return [pscustomobject]@{ id = 'listAllSites'; status = 200; body = [pscustomobject]@{ value = @($Sites) } }
        }
        foreach ($Request in $Requests) {
            $Id = ($Request.url -split '/')[1]
            $Template = if ($Id -eq $script:SiteIds[0]) { 'GenericList' } else { 'DocumentLibrary' }
            [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = "list-$Id"; list = [pscustomobject]@{ template = $Template }; parentReference = [pscustomobject]@{ siteId = "contoso.sharepoint.com,$Id,web-$Id" } }
                    )
                }
            }
        }
    }
}

Describe 'Get-CIPPSharePointSiteUsageRows' {
    BeforeEach {
        $script:BulkUrls = [System.Collections.Generic.List[string]]::new()
        $script:ArchiveStatus = $null
    }

    It 'requests only the fields it reads' {
        $null = Get-CIPPSharePointSiteUsageRows -TenantFilter 'contoso.onmicrosoft.com'

        $script:AdminCall.RowLimit | Should -Be 5000
        $script:AdminCall.ViewFields | Should -Not -Contain 'GroupId'
        $script:AdminCall.ViewFields | Should -Contain 'StorageQuota'
        $script:BulkUrls[0] | Should -Match '\$select=id,createdDateTime,displayName,isPersonalSite,webUrl,sharepointIds&'
        @($script:BulkUrls | Where-Object { $_ -like '*/lists?*' }).Count | Should -Be 3
        $script:BulkUrls[1] | Should -Match '/lists\?\$select=id,list,parentReference$'
    }

    It 'builds an auto map URL only for sites with a document library' {
        $Built = Get-CIPPSharePointSiteUsageRows -TenantFilter 'contoso.onmicrosoft.com'
        $BySite = @{}
        foreach ($Site in $Built.SiteListing) { $BySite[$Site.sharepointIds.siteId] = $Site }

        $BySite[$script:SiteIds[0]].AutoMapUrl | Should -Be ''
        $BySite[$script:SiteIds[2]].AutoMapUrl | Should -Be "tenantId=tenant-guid&webId={web-$($script:SiteIds[2])}&siteid={$($script:SiteIds[2])}&webUrl=https://contoso.sharepoint.com/sites/$($script:SiteIds[2])&listId={list-$($script:SiteIds[2])}"
    }

    It 'asks SharePoint admin for the site archive state with fields it accepts' {
        $null = Get-CIPPSharePointSiteUsageRows -TenantFilter 'contoso.onmicrosoft.com'

        $script:AdminCall.ViewFields | Should -Contain 'ArchiveStatus'
        { New-CIPPSPOAdminListViewXml -ViewFields $script:AdminCall.ViewFields } | Should -Not -Throw
    }

    It 'gives a site whose archive state is <Raw> the state <Expected>' -ForEach @(
        @{ Raw = 'NotArchived'; Expected = 'active' }
        @{ Raw = ''; Expected = 'active' }
        @{ Raw = 'RecentlyArchived'; Expected = 'archived' }
        @{ Raw = 'FullyArchived'; Expected = 'archived' }
        @{ Raw = 'fullyArchived'; Expected = 'archived' }
        @{ Raw = 'Reactivating'; Expected = 'reactivating' }
        @{ Raw = 'Pending'; Expected = 'unknown' }
    ) {
        $script:ArchiveStatus = $Raw
        $Built = Get-CIPPSharePointSiteUsageRows -TenantFilter 'contoso.onmicrosoft.com'

        @($Built.SiteListing)[0].archiveStatus | Should -BeExactly $Expected
    }

    It 'treats a site with no archive state as active' {
        $Built = Get-CIPPSharePointSiteUsageRows -TenantFilter 'contoso.onmicrosoft.com'

        @($Built.SiteListing)[0].archiveStatus | Should -BeExactly 'active'
    }
}

Describe 'ConvertTo-CIPPSharePointSiteUsagePayload' {
    It 'passes the site archive state through to the row' {
        $Site = [pscustomobject]@{ sharepointIds = [pscustomobject]@{ siteId = 'site-1' }; webUrl = 'https://c/s1'; archiveStatus = 'archived' }

        (ConvertTo-CIPPSharePointSiteUsagePayload -Site $Site).archiveStatus | Should -BeExactly 'archived'
    }

    It 'leaves the archive state empty for a site cached before it was collected' {
        $Site = [pscustomobject]@{ sharepointIds = [pscustomobject]@{ siteId = 'site-1' }; webUrl = 'https://c/s1' }
        $Row = ConvertTo-CIPPSharePointSiteUsagePayload -Site $Site

        $Row.PSObject.Properties['archiveStatus'] | Should -Not -BeNullOrEmpty
        $Row.archiveStatus | Should -BeNullOrEmpty
    }
}
