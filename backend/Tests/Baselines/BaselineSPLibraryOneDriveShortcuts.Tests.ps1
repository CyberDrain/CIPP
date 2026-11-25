# SPLibraryOneDriveShortcuts: the OneDriveLibraryShortcuts collector, the prepare hook's access and
# compliance decisions, the GraphBulkSweep write shape, and the REAL engine's verdict and hand-off.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $TableName) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly, $TableName) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Set-CIPPDBCacheUsers { param($TenantFilter) }
    function Set-CIPPDBCacheSharePointPermissions { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $extraHeaders, [switch]$UseCertificate, $AsApp) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp, $scope, $Version) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Get-CippException { param($Exception) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Test-CIPPBaselineCacheCollected.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselineGraphBulkSweep.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineSPLibraryOneDriveShortcutsState.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheOneDriveLibraryShortcuts.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/SharePoint Standards/SPLibraryOneDriveShortcuts.json') -Raw | ConvertFrom-Json

    $script:SiteId = 'contoso.sharepoint.com,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222'
    $script:SiteUrl = 'https://contoso.sharepoint.com/sites/Files'
    $script:ListUnique = 'aaaaaaaa-0000-0000-0000-000000000001'
    $script:ListInherit = 'aaaaaaaa-0000-0000-0000-000000000002'
    $script:GroupId = 'bbbbbbbb-0000-0000-0000-000000000001'
    $script:M365Id = 'cccccccc-0000-0000-0000-000000000001'

    $script:Users = @(
        [PSCustomObject]@{ id = 'u-bob'; userPrincipalName = 'bob@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-alice'; userPrincipalName = 'alice@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-carol'; userPrincipalName = 'carol@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-dave'; userPrincipalName = 'dave@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-off'; userPrincipalName = 'disabled@contoso.com'; accountEnabled = $false; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-guest'; userPrincipalName = 'guest#EXT#@contoso.com'; accountEnabled = $true; userType = 'Guest' }
    )

    function New-Grant {
        param($Scope = 'Library', $LibraryId = $script:ListUnique, $Login, $Type = 'User', $PrincipalId = '1', [switch]$Limited)
        [PSCustomObject]@{ rowType = 'Assignment'; siteId = $script:SiteId; siteUrl = $script:SiteUrl; scope = $Scope; libraryId = $(if ($Scope -eq 'Library') { $LibraryId }); principalId = $PrincipalId; principalType = $Type; loginName = $Login; isSystemManaged = [bool]$Limited }
    }
    $script:SiteRow = [PSCustomObject]@{ rowType = 'Site'; siteId = $script:SiteId; siteName = 'Files'; siteUrl = $script:SiteUrl; collectionStatus = 'Full' }
    function Set-DefaultGrants {
        $script:PermissionRows = @(
            $script:SiteRow
            New-Grant -Login 'i:0#.f|membership|bob@contoso.com'
            New-Grant -Login "c:0t.c|tenant|$script:GroupId" -Type 'Security Group'
            New-Grant -Login 'i:0#.f|membership|dave@contoso.com' -Limited
            New-Grant -Scope 'Site' -Login 'i:0#.f|membership|carol@contoso.com'
        )
    }
    $script:Drives = @(
        [PSCustomObject]@{ id = 'b!unique'; name = 'Accounting'; sharePointIds = [PSCustomObject]@{ listId = $script:ListUnique } }
        [PSCustomObject]@{ id = 'b!inherit'; name = 'Documents'; sharePointIds = [PSCustomObject]@{ listId = $script:ListInherit } }
    )
    function New-Shortcuts { param($Rows) @($Rows) | ConvertTo-Json -Depth 5 | ConvertFrom-Json }
    $script:DefaultShortcuts = @(
        [PSCustomObject]@{ id = 'u-bob'; userPrincipalName = 'bob@contoso.com'; driveIds = @() }
        [PSCustomObject]@{ id = 'u-alice'; userPrincipalName = 'alice@contoso.com'; driveIds = @('b!unique') }
        [PSCustomObject]@{ id = 'u-carol'; userPrincipalName = 'carol@contoso.com'; driveIds = @() }
        [PSCustomObject]@{ id = 'u-dave'; userPrincipalName = 'dave@contoso.com'; driveIds = @() }
    )
    function New-HookItem {
        param($Variables = @{})
        $Base = [ordered]@{ siteUrl = '/sites/Files'; destination = 'shortcuts' }
        foreach ($Key in $Variables.Keys) { $Base[$Key] = $Variables[$Key] }
        @{ TenantFilter = $script:Tenant; Variables = [PSCustomObject]$Base }
    }
    function New-EngineItem {
        @{ TenantFilter = $script:Tenant; Standard = 'SPLibraryOneDriveShortcuts'; BaseName = 'SPLibraryOneDriveShortcuts'; Variables = [PSCustomObject]@{ siteUrl = '/sites/Files'; destination = 'shortcuts' }; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
    function Use-HookMocks {
        Set-DefaultGrants
        $script:ShortcutRows = $script:DefaultShortcuts
        $script:GroupStatus = 200
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheSharePointPermissions {}
        Mock Get-CIPPDbItem { [PSCustomObject]@{ DataCount = 5; Timestamp = (Get-Date) } }
        Mock New-CIPPDbRequest {
            switch ($Type) {
                'SharePointPermissions' { $script:PermissionRows }
                'Users' { $script:Users }
                'OneDriveLibraryShortcuts' { New-Shortcuts $script:ShortcutRows }
            }
        }
        Mock New-GraphGetRequest { $script:Drives } -ParameterFilter { $uri -like '*graph.microsoft.com*/drives*' }
        Mock New-GraphGetRequest { @([PSCustomObject]@{ LoginName = 'i:0#.f|membership|carol@contoso.com' }) } -ParameterFilter { $uri -like '*/_api/web/sitegroups/*' }
        Mock New-GraphBulkRequest {
            foreach ($Request in @($Requests)) {
                $Upn = if ($Request.id -like 'owners-*') { 'carol@contoso.com' } else { 'alice@contoso.com' }
                [PSCustomObject]@{ id = $Request.id; status = $script:GroupStatus; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ userPrincipalName = $Upn }) } }
            }
        }
    }
}

Describe 'SPLibraryOneDriveShortcuts definition' {
    It 'is a per-site instance standard that reads its own on-demand cache through requiredCaches' {
        $script:Definition.multiple | Should -BeTrue
        $script:Definition.instanceIdentity | Should -Be 'siteUrl'
        $script:Definition.prepare | Should -Be 'Get-CIPPBaselineSPLibraryOneDriveShortcutsState'
        $script:Definition.read.cacheType | Should -Be 'OneDriveLibraryShortcuts'
        @($script:Definition.read.requiredCaches) | Should -Contain 'OneDriveLibraryShortcuts'
        $Registered = Get-Content (Join-Path $script:RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json
        @($Registered.type) | Should -Contain 'OneDriveLibraryShortcuts'
    }

    It 'uses no write token that a declared variable would overwrite' {
        $Declared = @($script:Definition.variables.PSObject.Properties.Name)
        $Json = $script:Definition.remediate | ConvertTo-Json -Depth 10
        $Tokens = @([regex]::Matches($Json, '%([A-Za-z0-9]+)%') | ForEach-Object { $_.Groups[1].Value })
        $Tokens.Count | Should -BeGreaterThan 0
        @($Tokens.Where({ $Declared -contains $_ })) | Should -BeNullOrEmpty
    }
}

Describe 'Set-CIPPDBCacheOneDriveLibraryShortcuts' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock Set-CIPPDBCacheUsers {}
        Mock New-CIPPDbRequest { $script:Users }
        $script:FolderStatus = 200
        Mock New-GraphBulkRequest {
            if (@($Requests)[0].url -like '*/drive/root/children*') {
                @(
                    [PSCustomObject]@{ id = 'u-bob'; status = 200; body = [PSCustomObject]@{ value = @(
                                [PSCustomObject]@{ id = 'i1'; remoteItem = [PSCustomObject]@{ id = 'r1'; parentReference = [PSCustomObject]@{ driveId = 'b!zeta' } } }
                                [PSCustomObject]@{ id = 'f-bob'; specialFolder = [PSCustomObject]@{ name = 'shortcuts' } }
                                [PSCustomObject]@{ id = 'i2' }
                            )
                        }
                    }
                    [PSCustomObject]@{ id = 'u-alice'; status = 200; body = [PSCustomObject]@{ value = @() } }
                    [PSCustomObject]@{ id = 'u-carol'; status = 404; body = [PSCustomObject]@{} }
                    [PSCustomObject]@{ id = 'u-dave'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'f-dave'; specialFolder = [PSCustomObject]@{ name = 'shortcuts' } }) } }
                )
            } else {
                @(
                    [PSCustomObject]@{ id = 'u-bob'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'i3'; remoteItem = [PSCustomObject]@{ id = 'r3'; parentReference = [PSCustomObject]@{ driveId = 'b!Alpha' } } }) } }
                    [PSCustomObject]@{ id = 'u-dave'; status = $script:FolderStatus; body = [PSCustomObject]@{ value = @(); error = [PSCustomObject]@{ message = 'boom' } } }
                )
            }
        }
    }

    It 'lists enabled members'' roots in one batch, then only the Shortcuts folders that exist' {
        Set-CIPPDBCacheOneDriveLibraryShortcuts -TenantFilter $script:Tenant
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            (@($Requests.id) -join ',') -eq 'u-bob,u-alice,u-carol,u-dave' -and
            @($Requests).Where({ $_.headers.Prefer -ne 'Include-Feature=AddToOneDrive' -or $_.url -notlike 'users/*/drive/root/children*' }).Count -eq 0 -and
            $asapp -eq $true
        }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            (@($Requests.url) -join ',') -eq 'users/u-bob/drive/items/f-bob/children?$select=id,remoteItem&$top=999,users/u-dave/drive/items/f-dave/children?$select=id,remoteItem&$top=999'
        }
    }

    It 'writes one row per OneDrive with sorted drive ids from the root and the Shortcuts folder, and no names' {
        Set-CIPPDBCacheOneDriveLibraryShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Bob = @($Data).Where({ $_.id -eq 'u-bob' })[0]
            $Type -eq 'OneDriveLibraryShortcuts' -and $AddCount -and $ClearOnEmpty -and
            (@($Data.id | Sort-Object) -join ',') -eq 'u-alice,u-bob,u-dave' -and
            (@($Bob.driveIds) -join ',') -eq 'b!Alpha,b!zeta' -and
            (@($Bob.PSObject.Properties.Name) -join ',') -eq 'id,userPrincipalName,driveIds'
        }
    }

    It 'drops a user whose Shortcuts folder could not be read and warns' {
        $script:FolderStatus = 500
        Set-CIPPDBCacheOneDriveLibraryShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { (@($Data.id | Sort-Object) -join ',') -eq 'u-alice,u-bob' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*dave@contoso.com*' }
    }

    It 'writes nothing when every listing fails, so the previous verdict stands' {
        Mock New-GraphBulkRequest { @(foreach ($Request in @($Requests)) { [PSCustomObject]@{ id = $Request.id; status = 403; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'denied' } } } }) }
        Set-CIPPDBCacheOneDriveLibraryShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }

    It 'records an empty set when nobody has a OneDrive yet' {
        Mock New-GraphBulkRequest { @(foreach ($Request in @($Requests)) { [PSCustomObject]@{ id = $Request.id; status = 404; body = [PSCustomObject]@{} } }) }
        Set-CIPPDBCacheOneDriveLibraryShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { @($Data).Where({ $_ }).Count -eq 0 -and $ClearOnEmpty }
    }
}

Describe 'Get-CIPPBaselineSPLibraryOneDriveShortcutsState' {
    BeforeEach { Use-HookMocks }

    It 'grades each library on its own grants, or the site''s when it inherits, ignoring Limited Access' {
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        # Accounting (unique): bob directly, alice via the security group but she already has it, dave only Limited Access.
        # Documents (inherits): carol through the site grant.
        @($Result.Current.offenders) | Should -Be @('bob@contoso.com: Accounting', 'carol@contoso.com: Documents')
    }

    It 'treats a user with any shortcut into the library''s drive as compliant' {
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        @($Result.Current.offenders) | Should -Not -Contain 'alice@contoso.com: Accounting'
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            (@($Requests.url) -join ',') -eq "groups/$script:GroupId/transitiveMembers/microsoft.graph.user?`$select=userPrincipalName&`$top=999"
        }
    }

    It 'skips users without a OneDrive, disabled accounts and guests' {
        $script:PermissionRows += New-Grant -Login 'i:0#.f|membership|disabled@contoso.com'
        $script:PermissionRows += New-Grant -Login 'i:0#.f|membership|guest#EXT#@contoso.com'
        $script:ShortcutRows = @($script:DefaultShortcuts.Where({ $_.id -ne 'u-bob' }))
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        @($Result.Current.offenders) | Should -Be @('carol@contoso.com: Documents')
    }

    It 'expands SharePoint groups through the site''s REST endpoint and Microsoft 365 owner claims through owners' {
        $script:PermissionRows = @(
            $script:SiteRow
            New-Grant -Scope 'Site' -Login 'Files Members' -Type 'SharePoint Group' -PrincipalId '7'
            New-Grant -Login "c:0o.c|federateddirectoryclaimprovider|$($script:M365Id)_o" -Type 'M365 Group'
        )
        $script:ShortcutRows = @([PSCustomObject]@{ id = 'u-carol'; userPrincipalName = 'carol@contoso.com'; driveIds = @() })
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        @($Result.Current.offenders) | Should -Be @('carol@contoso.com: Accounting', 'carol@contoso.com: Documents')
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "$script:SiteUrl/_api/web/sitegroups/getbyid(7)/users?`$select=LoginName" -and $scope -eq 'https://contoso.sharepoint.com/.default' -and $UseCertificate
        }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests)[0].url -like "groups/$script:M365Id/owners/*" }
    }

    It 'ignores Everyone except external users unless the tenant-wide option is on (<Include>)' -ForEach @(
        @{ Include = $false; Expected = @('carol@contoso.com: Documents') }
        @{ Include = $true; Expected = @('alice@contoso.com: Documents', 'bob@contoso.com: Documents', 'carol@contoso.com: Documents', 'dave@contoso.com: Documents') }
    ) {
        $script:PermissionRows = @(
            $script:SiteRow
            New-Grant -LibraryId $script:ListUnique -Login 'i:0#.f|membership|alice@contoso.com'
            New-Grant -Scope 'Site' -Login 'c:0-.f|rolemanager|spo-grid-all-users/00000000-0000-0000-0000-000000000000' -Type 'Security Group'
            New-Grant -Scope 'Site' -Login 'i:0#.f|membership|carol@contoso.com'
        )
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem @{ includeTenantWide = $Include }) -TenantFilter $script:Tenant
        @($Result.Current.offenders) | Should -Be $Expected
    }

    It 'honours excluded users and libraries, including picker wrappers' {
        $Item = New-HookItem @{ excludeUsers = @([PSCustomObject]@{ label = 'Carol'; value = 'carol@contoso.com' }); excludeLibraries = @('accounting') }
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item $Item -TenantFilter $script:Tenant
        @($Result.Current.offenders) | Should -BeNullOrEmpty
    }

    It 'builds the write target from the cache, the drive and the destination (<Destination>)' -ForEach @(
        @{ Destination = 'shortcuts'; Parent = 'special/shortcuts' }
        @{ Destination = 'root'; Parent = 'root' }
    ) {
        $script:SiteRow.siteName = 'Files: Main'
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem @{ destination = $Destination }) -TenantFilter $script:Tenant
        $script:SiteRow.siteName = 'Files'
        $Target = @($Result.Current.targets).Where({ $_.userId -eq 'u-bob' })[0]
        $Target.parentPath | Should -Be $Parent
        $Target.shortcutName | Should -Be 'Files- Main - Accounting'
        $Target.spListId | Should -Be $script:ListUnique
        $Target.spSiteId | Should -Be '11111111-1111-1111-1111-111111111111'
        $Target.spWebId | Should -Be '22222222-2222-2222-2222-222222222222'
        $Target.spSiteUrl | Should -Be $script:SiteUrl
    }

    It 'matches the site by full URL as well as by path' {
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem @{ siteUrl = 'https://contoso.sharepoint.com/sites/files/' }) -TenantFilter $script:Tenant
        @($Result.Current.offenders).Count | Should -Be 2
    }

    It 'reports a configuration error for a site the scan does not know' {
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem @{ siteUrl = '/sites/Nope' }) -TenantFilter $script:Tenant
        $Result.Current | Should -BeNullOrEmpty
        $Result.ConfigError | Should -BeTrue
        $Result.NoDataReason | Should -BeLike '*/sites/Nope*'
    }

    It 'starts the SharePoint permissions scan when it has never run, and grades nothing' {
        Mock Get-CIPPDbItem {}
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        $Result.Current | Should -BeNullOrEmpty
        Should -Invoke Set-CIPPDBCacheSharePointPermissions -Times 1 -Exactly
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'refreshes a permissions scan older than a day but still grades on it' {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ DataCount = 5; Timestamp = (Get-Date).AddDays(-2) } }
        $Result = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        Should -Invoke Set-CIPPDBCacheSharePointPermissions -Times 1 -Exactly
        @($Result.Current.offenders).Count | Should -Be 2
    }

    It 'treats a deleted group as having no members, and any other lookup failure as No Data' {
        $script:GroupStatus = 404
        $Deleted = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        @($Deleted.Current.offenders) | Should -Be @('bob@contoso.com: Accounting', 'carol@contoso.com: Documents')
        $script:GroupStatus = 403
        $Failed = Get-CIPPBaselineSPLibraryOneDriveShortcutsState -Item (New-HookItem) -TenantFilter $script:Tenant
        $Failed.Current | Should -BeNullOrEmpty
        $Failed.NoDataReason | Should -BeLike '*403*'
    }
}

Describe 'SPLibraryOneDriveShortcuts write spec through GraphBulkSweep' {
    It 'creates a whole-library shortcut by SharePoint ids in the chosen folder, app-only' {
        Mock Write-LogMessage {}
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = '0'; status = 201 }) }
        $Target = [PSCustomObject]@{ userId = 'u-bob'; parentPath = 'special/shortcuts'; shortcutName = 'Files - Accounting'; spListId = 'l1'; spSiteId = 's1'; spWebId = 'w1'; spSiteUrl = $script:SiteUrl }
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $script:Definition.remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ targets = @($Target) })
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $Request = @($Requests)[0]
            $Ids = $Request.body.remoteItem.sharepointIds
            $Request.method -eq 'POST' -and $Request.url -eq '/users/u-bob/drive/special/shortcuts/children' -and
            $Request.body.name -eq 'Files - Accounting' -and $Request.body.'@microsoft.graph.conflictBehavior' -eq 'rename' -and
            $Ids.listId -eq 'l1' -and $Ids.listItemUniqueId -eq 'root' -and $Ids.siteId -eq 's1' -and $Ids.webId -eq 'w1' -and $Ids.siteUrl -eq $script:SiteUrl -and
            $asapp -eq $true
        }
    }
}

Describe 'SPLibraryOneDriveShortcuts through the engine' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheOneDriveLibraryShortcuts {}
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTSTANDARD = $true } }
        Mock Invoke-CIPPBaselineGraphBulkSweep {}
    }

    It 'is compliant with no missing shortcuts and writes nothing' {
        Mock Get-CIPPBaselineSPLibraryOneDriveShortcutsState { @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() } } }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Result.Compliant | Should -BeTrue
        Should -Invoke Invoke-CIPPBaselineGraphBulkSweep -Times 0 -Exactly
    }

    It 'grades missing shortcuts as drift and hands GraphBulkSweep the targets with the write tokens intact' {
        $Target = [PSCustomObject]@{ userId = 'u-bob'; parentPath = 'special/shortcuts'; shortcutName = 'Files - Accounting'; spListId = 'l1'; spSiteId = 's1'; spWebId = 'w1'; spSiteUrl = $script:SiteUrl }
        Mock Get-CIPPBaselineSPLibraryOneDriveShortcutsState { @{ Current = [PSCustomObject]@{ offenders = @('bob@contoso.com: Accounting'); targets = @($Target) } } }
        $Compare = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare'
        $Compare.Outcome | Should -Be 'Drift'
        $Run = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Run.Remediated | Should -BeTrue
        Should -Invoke Invoke-CIPPBaselineGraphBulkSweep -Times 1 -Exactly -ParameterFilter {
            $Current.targets[0].userId -eq 'u-bob' -and
            $Remediate.writes[0].uri -eq 'users/%userId%/drive/%parentPath%/children' -and
            $Remediate.writes[0].body.remoteItem.sharepointIds.siteUrl -eq '%spSiteUrl%'
        }
    }
}
