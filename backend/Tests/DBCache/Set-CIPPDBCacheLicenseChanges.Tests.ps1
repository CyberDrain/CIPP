# Pester tests for ConvertFrom-CIPPLicenseAuditEvent, Set-CIPPDBCacheLicenseChanges and Invoke-ListLicenseChanges
# A licence change arrives as several audit events that each hold one chunk of the old and new licence lists;
# the chunks are joined per change, and a tenant whose log was read and held no change lists as empty, not as 404.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp, $body) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$ByTenant) }
    function Get-CIPPLicenseSkuName { param($SkuIds, $TenantFilter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertFrom-CIPPLicenseAuditEvent.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheLicenseChanges.ps1')
    $Endpoint = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Reports/Invoke-ListLicenseChanges.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Endpoint -Raw)))

    $script:SkuE3 = '05e9a617-0261-4cee-bb44-138d3ef5d965'
    $script:SkuFlow = 'f30db892-07e9-47e9-837c-80727f46fd3d'
    $script:UserActor = [pscustomobject]@{ app = $null; user = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'admin@contoso.com' } }

    function script:New-Sku {
        param($Name, $Id, $DisabledPlans = '')
        "[SkuName=$Name, AccountId=acc-1, SkuId=$Id, DisabledPlans=[$DisabledPlans]]"
    }

    function script:New-LicenseEvent {
        param($Id = 'evt', $Actor = $script:UserActor, $Details = @(), $Targets, $Result = 'success')
        [pscustomobject]@{
            id                  = $Id
            activityDateTime    = '2026-11-20T10:00:00Z'
            activityDisplayName = 'Change user license'
            result              = $Result
            initiatedBy         = $Actor
            targetResources     = $Targets ?? @([pscustomobject]@{ id = 'user-1'; type = 'User'; userPrincipalName = 'megan@contoso.com'; modifiedProperties = @() })
            additionalDetails   = @(foreach ($Key in $Details.Keys) { [pscustomobject]@{ key = $Key; value = [string]$Details[$Key] } })
        }
    }

    # The events Entra writes for one change: the blob cut into $Chunks pieces, one event per piece
    function script:New-ChunkedChange {
        param([string[]]$Old = @(), [string[]]$New = @(), $Chunks = 3, $BlobId = 'blob-1', $Actor = $script:UserActor)
        $Inner = ConvertTo-Json -Compress -InputObject @(
            @{ Name = 'AssignedPlan'; OldValue = @(); NewValue = @('padding ' * 20) }
            @{ Name = 'AssignedLicense'; OldValue = $Old; NewValue = $New }
        )
        $Blob = ConvertTo-Json -Compress -InputObject @{ targetUpdatedProperties = $Inner }
        $Size = [Math]::Ceiling($Blob.Length / $Chunks)
        foreach ($Seq in 1..$Chunks) {
            $Offset = ($Seq - 1) * $Size
            script:New-LicenseEvent -Id "evt-$BlobId-$Seq" -Actor $Actor -Details ([ordered]@{
                    id = $BlobId; seq = $Seq; b = $Blob.Substring($Offset, [Math]::Min($Size, $Blob.Length - $Offset)); c = $Chunks
                })
        }
    }
}

Describe 'ConvertFrom-CIPPLicenseAuditEvent' {
    BeforeEach {
        Mock Get-CIPPLicenseSkuName { [pscustomobject]@{ skuId = $script:SkuFlow; displayName = 'Microsoft Power Automate Free' } }
    }

    It 'joins the chunks of a change whatever order they arrive in' {
        $Events = @(script:New-ChunkedChange -Old (script:New-Sku 'ENTERPRISEPACK' $script:SkuE3) -New (script:New-Sku 'ENTERPRISEPACK' $script:SkuE3), (script:New-Sku 'FLOW_FREE' $script:SkuFlow))
        [array]::Reverse($Events)

        $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events -TenantFilter 'contoso.onmicrosoft.com')

        $Rows.Count | Should -Be 1
        $Rows[0].id | Should -BeExactly "evt-blob-1-1-user-1-$script:SkuFlow"
        $Rows[0].change | Should -BeExactly 'Added'
        $Rows[0].skuPartNumber | Should -BeExactly 'FLOW_FREE'
        $Rows[0].license | Should -BeExactly 'Microsoft Power Automate Free'
        $Rows[0].userId | Should -BeExactly 'user-1'
        $Rows[0].userPrincipalName | Should -BeExactly 'megan@contoso.com'
        $Rows[0].initiatedByType | Should -BeExactly 'User'
        $Rows[0].initiatedBy | Should -BeExactly 'admin@contoso.com'
    }

    It 'reports a licence that left the list as removed and falls back to the SKU name' {
        $Events = @(script:New-ChunkedChange -Old (script:New-Sku 'ENTERPRISEPACK' $script:SkuE3) -New @())

        $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events)

        $Rows.Count | Should -Be 1
        $Rows[0].change | Should -BeExactly 'Removed'
        $Rows[0].license | Should -BeExactly 'ENTERPRISEPACK'
    }

    It 'keeps two changes apart' {
        $Events = @(
            script:New-ChunkedChange -BlobId 'blob-1' -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow)
            script:New-ChunkedChange -BlobId 'blob-2' -Old (script:New-Sku 'FLOW_FREE' $script:SkuFlow)
        )

        $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events)

        @($Rows.change | Sort-Object) | Should -Be @('Added', 'Removed')
    }

    It 'skips a change with a chunk missing' {
        $Events = @(script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow))

        @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events[0, 2]).Count | Should -Be 0
    }

    It 'returns nothing when only the disabled service plans changed' {
        $Events = @(script:New-ChunkedChange -Old (script:New-Sku 'ENTERPRISEPACK' $script:SkuE3) -New (script:New-Sku 'ENTERPRISEPACK' $script:SkuE3 'plan-1'))

        @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events).Count | Should -Be 0
    }

    It 'skips a chunk with an unreadable sequence number and keeps the other changes' {
        $Broken = script:New-LicenseEvent -Details ([ordered]@{ id = 'blob-bad'; seq = 'bad'; b = 'x'; c = 'two' })
        $Events = @($Broken) + @(script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow))

        @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events).Count | Should -Be 1
    }

    It 'ignores a change that failed' {
        $Events = @(script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow) | ForEach-Object { $_.result = 'failure'; $_ })

        @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events).Count | Should -Be 0
    }

    It 'reads piped events' {
        @(script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow) | ConvertFrom-CIPPLicenseAuditEvent).Count | Should -Be 1
    }

    It 'reads the lists from modifiedProperties per user when the event carries them there' {
        $Property = [pscustomobject]@{
            displayName = 'AssignedLicense'
            oldValue    = '[]'
            newValue    = ConvertTo-Json -Compress -InputObject @(script:New-Sku 'FLOW_FREE' $script:SkuFlow)
        }
        $Targets = @(
            [pscustomobject]@{ id = 'user-a'; type = 'User'; userPrincipalName = 'a@contoso.com'; modifiedProperties = @($Property) }
            [pscustomobject]@{ id = 'user-b'; type = 'User'; userPrincipalName = 'b@contoso.com'; modifiedProperties = @($Property) }
        )

        $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events @(script:New-LicenseEvent -Targets $Targets))

        $Rows.userPrincipalName | Should -Be @('a@contoso.com', 'b@contoso.com')
        $Rows[0].id | Should -Not -Be $Rows[1].id
        $Rows[0].change | Should -BeExactly 'Added'
        $Rows[0].skuId | Should -BeExactly $script:SkuFlow
    }

    It 'names the app that made the change' {
        $Actor = [pscustomobject]@{ user = $null; app = [pscustomobject]@{ appId = 'app-1'; displayName = 'Microsoft Azure AD Group-Based Licensing'; servicePrincipalId = 'sp-1' } }

        $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events @(script:New-ChunkedChange -Actor $Actor -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow)))

        $Rows[0].initiatedByType | Should -BeExactly 'Application'
        $Rows[0].initiatedBy | Should -BeExactly 'Microsoft Azure AD Group-Based Licensing'
    }

    Context 'a partner technician made the change' {
        BeforeAll {
            $script:PreviousTenantId = $env:TenantID
            $env:TenantID = 'partner-tenant'
            $script:Technician = [pscustomobject]@{ app = $null; user = [pscustomobject]@{ id = 'tech-1'; userPrincipalName = 'user_tech1@partner.com'; homeTenantId = 'partner-tenant' } }
        }
        AfterAll { $env:TenantID = $script:PreviousTenantId }

        It 'shows the UPN the technician has in the partner tenant' {
            Mock New-GraphPOSTRequest { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'tech-1'; userPrincipalName = 'kim@partner.com' }) } }
            $Events = @(
                script:New-ChunkedChange -BlobId 'blob-1' -Actor $script:Technician -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow)
                script:New-ChunkedChange -BlobId 'blob-2' -Old (script:New-Sku 'FLOW_FREE' $script:SkuFlow)
            )

            $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events)

            $Rows.Where({ $_.change -eq 'Added' })[0].initiatedBy | Should -BeExactly 'kim@partner.com'
            $Rows.Where({ $_.change -eq 'Removed' })[0].initiatedBy | Should -BeExactly 'admin@contoso.com'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'partner-tenant' -and $uri -like '*getByIds*' -and $body -like '*tech-1*' }
        }

        It 'keeps the logged name when the lookup fails' {
            Mock New-GraphPOSTRequest { throw 'Forbidden' }

            $Rows = @(ConvertFrom-CIPPLicenseAuditEvent -Events @(script:New-ChunkedChange -Actor $script:Technician -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow)))

            $Rows[0].initiatedBy | Should -BeExactly 'user_tech1@partner.com'
        }
    }

    It 'ignores other events' {
        $Events = @(script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow) | ForEach-Object { $_.activityDisplayName = 'Update user'; $_ })

        @(ConvertFrom-CIPPLicenseAuditEvent -Events $Events).Count | Should -Be 0
    }
}

Describe 'Set-CIPPDBCacheLicenseChanges' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
        Mock Get-CIPPLicenseSkuName { }
    }

    It 'reads 30 days of licence changes app-only and caches them' {
        Mock New-GraphGetRequest { script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow) }

        Set-CIPPDBCacheLicenseChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -match "directoryAudits\?\`$filter=activityDisplayName eq 'Change user license' and activityDateTime ge (?<start>[^&]+)&.*additionalDetails" -and
            [Math]::Abs(([datetime]::UtcNow.AddDays(-30) - [datetime]::Parse($Matches['start']).ToUniversalTime()).TotalMinutes) -lt 5 -and
            $tenantid -eq 'contoso.onmicrosoft.com' -and $AsApp -and $Stream
        }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' -and $Type -eq 'LicenseChanges' -and @($Data).Count -eq 1 -and $AddCount -and -not $ClearOnEmpty }
    }

    It 'records an empty set when no licence changed' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheLicenseChanges -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'writes nothing and rethrows when the audit log cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' }

        { Set-CIPPDBCacheLicenseChanges -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*Forbidden*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}

Describe 'Invoke-ListLicenseChanges' {
    BeforeAll {
        function script:Get-Changes {
            param($Tenant = 'contoso.onmicrosoft.com', $UseReportDB)
            Invoke-ListLicenseChanges -Request ([pscustomobject]@{ Params = @{}; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = $Tenant; UseReportDB = $UseReportDB } })
        }
        $script:CountRow = [pscustomobject]@{ RowKey = 'LicenseChanges-Count'; Timestamp = [datetime]'2026-11-20T02:00:00Z'; DataCount = 0 }
        $script:DataRow = [pscustomobject]@{ RowKey = 'LicenseChanges-x'; Timestamp = [datetime]'2026-11-20T02:00:00Z'; Data = '{"change":"Added","skuId":"sku-1"}' }
    }

    BeforeEach {
        Mock Write-LogMessage { }
        Mock Get-CIPPLicenseSkuName { }
        Mock New-GraphGetRequest { script:New-ChunkedChange -New (script:New-Sku 'FLOW_FREE' $script:SkuFlow) }
    }

    It 'reads the audit log live by default' {
        Mock Get-CIPPDbItem { }

        $Response = script:Get-Changes

        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 1
        Should -Invoke Get-CIPPDbItem -Times 0
    }

    It 'marks only the newest change of a licence on a user as the latest' {
        Mock Get-CIPPDbItem {
            $script:CountRow
            [pscustomobject]@{ RowKey = 'LicenseChanges-1'; Timestamp = [datetime]'2026-11-20T02:00:00Z'; Data = '{"id":"old","activityDateTime":"2026-11-10T10:00:00Z","userId":"u1","skuId":"sku-1"}' }
            [pscustomobject]@{ RowKey = 'LicenseChanges-2'; Timestamp = [datetime]'2026-11-20T02:00:00Z'; Data = '{"id":"new","activityDateTime":"2026-11-12T10:00:00Z","userId":"u1","skuId":"sku-1"}' }
            [pscustomobject]@{ RowKey = 'LicenseChanges-3'; Timestamp = [datetime]'2026-11-20T02:00:00Z'; Data = '{"id":"other","activityDateTime":"2026-11-11T10:00:00Z","userId":"u2","skuId":"sku-1"}' }
        }

        $Body = (script:Get-Changes -UseReportDB $true).Body

        $Body.id | Should -Be @('new', 'other', 'old')
        $Body.latestChange | Should -Be @($true, $true, $false)
    }

    It 'serves the cache with its timestamp when asked to' {
        Mock Get-CIPPDbItem { $script:CountRow; $script:DataRow }

        $Response = script:Get-Changes -UseReportDB $true

        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 1
        $Response.Body[0].change | Should -BeExactly 'Added'
        $Response.Body[0].CacheTimestamp | Should -Be $script:DataRow.Timestamp
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'lists nothing for a tenant whose log was read and held no change' {
        Mock Get-CIPPDbItem { $script:CountRow }

        $Response = script:Get-Changes -UseReportDB $true

        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 0
    }

    It 'answers 404 when the tenant was never synced' {
        Mock Get-CIPPDbItem { }

        $Response = script:Get-Changes -UseReportDB $true

        $Response.StatusCode | Should -Be 404
        $Response.Body.Error | Should -BeLike '*Sync the report data first*'
    }

    It 'reads every tenant from the cache and names the tenant on each row' {
        Mock Get-CIPPDbItem { [ordered]@{ 'contoso.onmicrosoft.com' = @($script:DataRow); 'fabrikam.onmicrosoft.com' = @($script:DataRow) } } -ParameterFilter { $ByTenant }

        $Response = script:Get-Changes -Tenant 'AllTenants'

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Tenant) | Should -Be @('contoso.onmicrosoft.com', 'fabrikam.onmicrosoft.com')
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'answers 500 when the audit log cannot be read' {
        Mock New-GraphGetRequest { throw 'Graph is down' }

        (script:Get-Changes).StatusCode | Should -Be 500
    }
}
