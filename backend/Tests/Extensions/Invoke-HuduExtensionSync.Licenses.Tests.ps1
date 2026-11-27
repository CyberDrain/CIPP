BeforeAll {
    # The sync reads its config from the Extensionsconfig table; this stores what that read returns.
    function Invoke-HuduSyncWithConfig { param($Configuration, $TenantFilter) $script:HuduConfig = $Configuration; Invoke-HuduExtensionSync -TenantFilter $TenantFilter }
    Add-Type -Path "$PSScriptRoot/../../Shared/CIPPSharp/bin/CIPPSharp.dll"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Invoke-HuduExtensionSync.ps1"
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Documentation/*.ps1", "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }
    . "$PSScriptRoot/../../Modules/CippExtensions/Private/Get-CippExtensionCulture.ps1"

    function Connect-HuduAPI { param($Configuration) }
    function Get-HuduAppInfo { [CmdletBinding()] param() [PSCustomObject]@{ version = '2.46.1'; date = '2026-09-01' } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-AssignedNameMap { }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Get-CippExtensionReportingData { param($TenantFilter, [switch]$IncludeMailboxes, [string[]]$Exclude) }
    function Get-HuduCompanies { param($Id) }
    function Add-HuduAssetLayoutField { param($AssetLayoutId, $Label, $FieldType, $Position, $ShowInList, $AssetLayout) }
    function Get-HuduAssetLayouts { param($Id, $LayoutId) }
    function Get-HuduAssets { [CmdletBinding()] param($CompanyId, $AssetLayoutId, $Name, [switch]$Archived, $PrimarySerial) }
    function Get-HuduRelations { [CmdletBinding()] param() }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-StringHash { param($String) }
    function Set-HuduAsset { [CmdletBinding()] param([Alias('asset_id')]$AssetId, $Name, [Alias('company_id')]$CompanyId, [Alias('asset_layout_id')]$AssetLayoutId, $Fields, $PrimarySerial, $ExistingAsset) }
    function New-HuduAsset { [CmdletBinding()] param($Name, [Alias('company_id')]$CompanyId, [Alias('asset_layout_id')]$AssetLayoutId, $Fields, $PrimarySerial) }
    function Set-HuduMagicDash { param($Title, $CompanyName, $Message, $Icon, $Content, $Shade) }
    function Get-HuduMagicDashes { param($CompanyId) }
    function Write-LogMessage { param($Tenant, $TenantId, $API, $Message, $Level, $Sev) }
    function Get-CippException { param($Exception) return [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) }

    $script:PremiumSku = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'
    $script:DefenderSku = '4ef96642-f096-40de-a3e9-d83fb2f90211'
    function New-TestLicenseAsset {
        param($Id, $Name, $SkuId, [switch]$Archived)
        [PSCustomObject]@{
            id = $Id; name = $Name; asset_layout_id = 40; archived = [bool]$Archived
            fields = @(if ($SkuId) { [PSCustomObject]@{ label = 'SKU ID'; value = $SkuId } })
        }
    }
}

Describe 'Invoke-HuduExtensionSync license assets' {
    BeforeEach {
        $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path
        $Configuration = [PSCustomObject]@{
            Hudu = [PSCustomObject]@{
                IncludeLAPS = $false; IncludeBitLocker = $false
                CreateMissingUsers = $false; CreateMissingDevices = $false; CreateMissingLicenses = $true
                ImportDomains = $false; MonitorDomains = $false; HideEmptyRoles = $false
                IncludeDefenderLink = $false; IncludeComplianceLink = $false; IncludeParterCenterLink = $false
            }
        }
        $script:FieldMappings = @([PSCustomObject]@{ PartitionKey = 'HuduFieldMapping'; RowKey = 'Licenses'; IntegrationId = 40; IntegrationName = 'Licenses' })
        $script:LicenseCache = @(
            [PSCustomObject]@{
                skuId = $script:PremiumSku.ToUpper(); skuPartNumber = 'Microsoft 365 Business Premium'; consumedUnits = '1'; prepaidUnits = @{ enabled = '5' }
                TermInfo = @([PSCustomObject]@{ Status = 'Enabled'; Term = 'Yearly'; TotalLicenses = 5; NextLifecycle = '2099-03-01T00:00:00Z'; IsTrial = $false })
            }
            [PSCustomObject]@{ skuId = $script:DefenderSku; skuPartNumber = 'Microsoft Defender for Office 365 (Plan 1)'; consumedUnits = '0'; prepaidUnits = @{ enabled = '5' }; TermInfo = @() }
            [PSCustomObject]@{ skuId = '00000000-0000-4000-8000-000000000001'; skuPartNumber = 'Lapsed SKU'; consumedUnits = '0'; prepaidUnits = @{ enabled = '0' }; TermInfo = @() }
        )
        $script:LicenseLayout = [PSCustomObject]@{
            id     = 40
            fields = @(
                [PSCustomObject]@{ label = 'Seats Purchased'; position = 1; field_type = 'Number' }
                [PSCustomObject]@{ label = 'Seats Used'; position = 2; field_type = 'Text' }
                [PSCustomObject]@{ label = 'Renewal Date'; position = 3; field_type = 'Date' }
            )
        }
        $script:HuduLicenses = [System.Collections.Generic.List[object]]::new()
        $script:CachedLicenseRows = @()
        $script:Created = [System.Collections.Generic.List[object]]::new()
        $script:Updated = [System.Collections.Generic.List[object]]::new()

        Mock Connect-HuduAPI { }
        Mock Get-Tenants {
            [PSCustomObject]@{ displayName = 'Contoso'; defaultDomainName = 'contoso.onmicrosoft.com'; initialDomainName = 'contoso.onmicrosoft.com'; customerId = 'tenant-1' }
        }
        Mock Get-AssignedNameMap { [PSCustomObject]@{} }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { -not $Filter } { [pscustomobject]@{ config = ($script:HuduConfig | ConvertTo-Json -Depth 20) } }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'HuduMapping'*") {
                return @([PSCustomObject]@{ PartitionKey = 'HuduMapping'; RowKey = 'tenant-1'; IntegrationId = 20; IntegrationName = 'Contoso' }) + $script:FieldMappings
            }
            if ($Filter -like '*InstanceProperties*') { return [PSCustomObject]@{ Value = 'cipp.example.test' } }
            if ($Filter -like '*CacheMetadata*') { return [PSCustomObject]@{ LastRefresh = (Get-Date).ToUniversalTime().ToString('o') } }
            if ($Filter -eq "PartitionKey eq 'HuduLicense' and CompanyId eq '20'") { return $script:CachedLicenseRows }
            return $null
        }
        Mock Get-CippExtensionReportingData {
            [PSCustomObject]@{
                Users    = @([PSCustomObject]@{
                        id = 'user-1'; displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.onmicrosoft.com'; accountEnabled = $true
                        proxyAddresses = @('SMTP:jane@contoso.onmicrosoft.com'); businessPhones = @()
                        assignedLicenses = @([PSCustomObject]@{ skuId = $script:PremiumSku })
                    })
                AllRoles = @(); Domains = @(); Licenses = $script:LicenseCache; Devices = @()
                DeviceCompliancePolicies = @(); Groups = @(); ConditionalAccess = @()
                OneDriveUsage = @(); CASMailbox = @(); Mailboxes = @(); MailboxUsage = @(); MailboxPermissions = @()
            }
        }
        Mock Get-HuduCompanies { [PSCustomObject]@{ id = 20; name = 'Contoso'; archived = $false } }
        Mock Add-HuduAssetLayoutField { }
        Mock Get-HuduAssetLayouts { $script:LicenseLayout }
        Mock Get-HuduAssets { $script:HuduLicenses | Where-Object { [bool]$_.archived -eq [bool]$Archived } }
        Mock Get-HuduRelations { @() }
        Mock Get-CIPPDbItem { @() }
        Mock Get-StringHash { "hash-$($String.GetHashCode())" }
        Mock Add-CIPPAzDataTableEntity { $script:CachedLicenseRows = @($script:CachedLicenseRows) + @($Entity | Where-Object { $_.PartitionKey -eq 'HuduLicense' }) }
        Mock New-HuduAsset {
            $script:Created.Add([PSCustomObject]@{ Name = $Name; AssetLayoutId = $AssetLayoutId; Fields = $Fields })
            $Asset = New-TestLicenseAsset -Id (500 + $script:Created.Count) -Name $Name -SkuId $Fields.sku_id
            $script:HuduLicenses.Add($Asset)
            [PSCustomObject]@{ asset = $Asset }
        }
        Mock Set-HuduAsset { $script:Updated.Add([PSCustomObject]@{ Id = $AssetId; Name = $Name; Fields = $Fields }) }
        Mock Set-HuduMagicDash { }
        Mock Write-LogMessage { }
    }

    It 'creates an asset for each SKU with seats and adds only the missing layout fields' {
        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Result.Errors | Where-Object { $_ -like 'License *' -or $_ -like '*Licenses*' } | Should -BeNullOrEmpty
        $Result.Licenses | Should -Be 2
        $script:Created.Name | Should -Be @('Microsoft 365 Business Premium', 'Microsoft Defender for Office 365 (Plan 1)')
        $script:Created.AssetLayoutId | Should -Be @(40, 40)
        $Premium = $script:Created[0].Fields
        $Premium.sku_id | Should -Be $script:PremiumSku.ToUpper()
        $Premium.seats_purchased | Should -Be '5'
        $Premium.seats_used | Should -Be '1'
        $Premium.renewal_date | Should -Be '2099/03/01'
        $Premium.microsoft_365 | Should -Match 'Jane Doe'
        $Premium.microsoft_365 | Should -Match '>Synced '
        $script:Created[1].Fields.renewal_date | Should -Be ''
        Should -Invoke Add-HuduAssetLayoutField -Times 2 -Exactly
        Should -Invoke Add-HuduAssetLayoutField -Times 1 -Exactly -ParameterFilter { $AssetLayoutId -eq 40 -and $Label -eq 'Microsoft 365' -and $FieldType -eq 'RichText' }
        Should -Invoke Add-HuduAssetLayoutField -Times 1 -Exactly -ParameterFilter { $AssetLayoutId -eq 40 -and $Label -eq 'SKU ID' -and $FieldType -eq 'Text' }
        $script:CachedLicenseRows.RowKey | Sort-Object | Should -Be @('501', '502')
    }

    It 'adds the seat and renewal fields to a layout that lacks them' {
        $script:LicenseLayout.fields = @()
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-HuduAssetLayoutField -Times 5 -Exactly
        Should -Invoke Add-HuduAssetLayoutField -Times 1 -Exactly -ParameterFilter { $Label -eq 'Renewal Date' -and $FieldType -eq 'Date' -and $ShowInList -eq $true }
    }

    It 'updates the asset carrying the SKU ID and adopts one matched by name' {
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 301 -Name 'Renamed by the partner' -SkuId $script:PremiumSku))
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 302 -Name 'microsoft defender for office 365 (plan 1)'))

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Result.Errors | Where-Object { $_ -like 'License *' } | Should -BeNullOrEmpty
        Should -Invoke New-HuduAsset -Times 0 -Exactly
        $script:Updated.Id | Should -Be @(301, 302)
        $script:Updated[0].Name | Should -Be 'Renamed by the partner'
        $script:Updated[1].Fields.sku_id | Should -Be $script:DefenderSku
    }

    It 'writes nothing on a second sync when nothing changed' {
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-HuduAsset -Times 2 -Exactly
        Should -Invoke Set-HuduAsset -Times 0 -Exactly
    }

    It 'zeroes the asset of a SKU that has left the tenant' {
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 303 -Name 'Visio Plan 2' -SkuId 'c5928f49-12ba-48f7-ada3-0d743a3601d5'))

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Result.Licenses | Should -Be 2
        $script:Updated.Id | Should -Be @(303)
        $Fields = $script:Updated[0].Fields
        $Fields.seats_purchased | Should -Be '0'
        $Fields.seats_used | Should -Be '0'
        $Fields.Keys | Should -Not -Contain 'sku_id'
        $Fields.microsoft_365 | Should -Match 'Visio Plan 2'
        $Fields.microsoft_365 | Should -Match '>Not reported<'
    }

    It 'leaves every asset alone when the license cache is empty' {
        $script:LicenseCache = @()
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 303 -Name 'Visio Plan 2' -SkuId 'c5928f49-12ba-48f7-ada3-0d743a3601d5'))

        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Set-HuduAsset -Times 0 -Exactly
        Should -Invoke New-HuduAsset -Times 0 -Exactly
    }

    It 'does not recreate a license whose asset is archived' {
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 304 -Name 'Microsoft 365 Business Premium' -SkuId $script:PremiumSku -Archived))

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:Created.Name | Should -Be @('Microsoft Defender for Office 365 (Plan 1)')
        Should -Invoke Set-HuduAsset -Times 0 -Exactly
        $Result.Logs | Should -Contain 'Skipping Microsoft 365 Business Premium, it matches an archived asset in Hudu'
    }

    It 'reports a duplicate match instead of writing to either asset' {
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 305 -Name 'Premium A' -SkuId $script:PremiumSku))
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 306 -Name 'Premium B' -SkuId $script:PremiumSku))

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Set-HuduAsset -Times 0 -Exactly
        @($Result.Errors | Where-Object { $_ -like 'License Microsoft 365 Business Premium: Multiple assets matched in Hudu*' }) | Should -HaveCount 1
    }

    It 'reports a failed write and does not cache its hash' {
        Mock New-HuduAsset { throw 'Hudu returned 422' }

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Result.Licenses | Should -Be 0
        @($Result.Errors | Where-Object { $_ -like 'License *: Unable to sync the license to Hudu: Hudu returned 422' }) | Should -HaveCount 2
        Should -Invoke Write-LogMessage -Times 2 -Exactly -ParameterFilter { $Sev -eq 'Error' -and $Message -like 'License *: Unable to sync the license to Hudu: Hudu returned 422' }
        $script:CachedLicenseRows | Should -HaveCount 0
    }

    It 'only updates existing assets when creating missing licenses is off' {
        $Configuration.Hudu.CreateMissingLicenses = $false
        $script:HuduLicenses.Add((New-TestLicenseAsset -Id 301 -Name 'Microsoft 365 Business Premium' -SkuId $script:PremiumSku))

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-HuduAsset -Times 0 -Exactly
        $script:Updated.Id | Should -Be @(301)
        $Result.Licenses | Should -Be 1
        $Result.Errors | Where-Object { $_ -like 'License *' } | Should -BeNullOrEmpty
    }

    It 'takes the soonest upcoming term end among enabled subscriptions as the renewal date' {
        $script:LicenseCache[0].TermInfo = @(
            [PSCustomObject]@{ Status = 'Enabled'; Term = 'Yearly'; TotalLicenses = 3; NextLifecycle = '2099-03-01T00:00:00Z' }
            [PSCustomObject]@{ Status = 'Enabled'; Term = 'Monthly'; TotalLicenses = 2; NextLifecycle = '2098-12-15T00:00:00Z' }
            [PSCustomObject]@{ Status = 'Enabled'; Term = 'Yearly'; TotalLicenses = 1; NextLifecycle = '2020-01-01T00:00:00Z' }
            [PSCustomObject]@{ Status = 'Suspended'; Term = 'Monthly'; TotalLicenses = 4; NextLifecycle = '2098-01-01T00:00:00Z' }
        )
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Premium = $script:Created[0].Fields
        $Premium.renewal_date | Should -Be '2098/12/15'
        $Premium.microsoft_365 | Should -Match '>Renewal date</td><td[^>]*>15 Dec 2098<'
        $Premium.microsoft_365 | Should -Match 'A subscription is <strong>suspended</strong>'
    }

    It 'always flags an over-assigned license' {
        $script:LicenseCache[0].consumedUnits = '6'
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Body = $script:Created[0].Fields.microsoft_365
        $Body | Should -Match '>Over-assigned<'
        $Body | Should -Match '<strong>6 of 5</strong> seats assigned, more than purchased'
    }

    It 'flags a full or nearly full license only when the Magic Dash warning settings are on' {
        $script:LicenseCache[0].consumedUnits = '5'
        $script:LicenseCache[1].consumedUnits = '9'; $script:LicenseCache[1].prepaidUnits = @{ enabled = '10' }
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:Created[0].Fields.microsoft_365 | Should -Match '>Fully assigned<'
        $script:Created.Fields.microsoft_365 | Should -Not -Match 'Needs attention'

        $script:Created.Clear(); $script:HuduLicenses.Clear(); $script:CachedLicenseRows = @()
        $Configuration.Hudu | Add-Member -NotePropertyName ShowLicenseFullWarning -NotePropertyValue $true
        $Configuration.Hudu | Add-Member -NotePropertyName ShowLicenseNearFullWarning -NotePropertyValue $true
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:Created[0].Fields.microsoft_365 | Should -Match '<strong>Every seat</strong> is assigned'
        $script:Created[1].Fields.microsoft_365 | Should -Match '<strong>90%</strong> of seats are assigned'
    }

    It 'hashes the license body without the sync timestamp and writes it with one' {
        Mock Get-StringHash { $script:HashedLicenseBody = $String; 'license-hash' }
        $null = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $script:HashedLicenseBody | Should -Not -Match '>Synced '
        $script:Created[0].Fields.microsoft_365 | Should -Match '>Synced '
    }

    It 'logs a company-level failure when the license assets cannot be listed' {
        Mock Get-HuduAssets { throw 'Permissions scoped to company' }

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        @($Result.Errors | Where-Object { $_ -like 'Company: Unable to sync Licenses*Permissions scoped to company' }) | Should -HaveCount 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' -and $Message -like 'Company: Unable to sync Licenses*' }
        Should -Invoke New-HuduAsset -Times 0 -Exactly
    }

    It 'skips licenses when no license layout is mapped' {
        $script:FieldMappings = @()

        $Result = Invoke-HuduSyncWithConfig -Configuration $Configuration -TenantFilter 'contoso.onmicrosoft.com'

        $Result.Licenses | Should -Be 0
        $Result.Logs | Should -Not -Contain 'Starting License Processing'
        Should -Invoke Get-HuduAssets -Times 0 -Exactly
        Should -Invoke New-HuduAsset -Times 0 -Exactly
    }
}
