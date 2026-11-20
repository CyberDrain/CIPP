BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPIntuneSettingSearch { param($TenantFilter, $Search, $MaxResults) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSingleTenantFilter.ps1')
    function Get-NormalizedError { param($Message) $Message }
    function Add-CIPPIntuneSettingDeviceCount { param($TenantFilter, $Results) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneSettingSearch.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-Request([hashtable]$Query) {
        [PSCustomObject]@{ Query = [PSCustomObject]$Query }
    }

    function New-SettingRow([int]$Index) {
        [PSCustomObject]@{ SettingId = "id-$Index"; SettingName = "Name $Index"; Category = 'Cat'; PolicyTypes = 'Custom'; PolicyCount = 1; Policies = @() }
    }
}

Describe 'Invoke-ListIntuneSettingSearch' {
    BeforeEach {
        Mock Get-CIPPIntuneSettingSearch { New-SettingRow 1 }
        Mock Add-CIPPIntuneSettingDeviceCount { foreach ($Result in $Results) { $Result | Add-Member -NotePropertyName DeviceCount -NotePropertyValue 7 -Force } }
        Mock Write-LogMessage {}
    }

    It 'passes the tenant and trimmed search to the report' {
        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = '  password ' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 1
        $Response.Body.Results[0].PolicyTypes | Should -Be 'Custom'
        $Response.Body.Metadata.Truncated | Should -BeFalse
        Should -Invoke Get-CIPPIntuneSettingSearch -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' -and $Search -eq 'password' }
    }

    It 'returns no rows without searching for <Name>' -ForEach @(
        @{ Name = 'one character'; Search = ' a ' }
        @{ Name = 'two characters'; Search = ' ab ' }
    ) {
        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = $Search }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        ($Response.Body | ConvertTo-Json -Depth 5 -Compress) | Should -BeLike '*"Results":`[`]*'
        $Response.Body.Metadata.Truncated | Should -BeFalse
        Should -Invoke Get-CIPPIntuneSettingSearch -Times 0 -Exactly
    }

    It 'searches with three characters' {
        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'pin' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        Should -Invoke Get-CIPPIntuneSettingSearch -Times 1 -Exactly
    }

    It 'returns exactly 500 settings without marking them truncated' {
        Mock Get-CIPPIntuneSettingSearch { 1..500 | ForEach-Object { New-SettingRow $_ } }

        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'password' }) -TriggerMetadata $null

        @($Response.Body.Results) | Should -HaveCount 500
        $Response.Body.Metadata.Truncated | Should -BeFalse
    }

    It 'returns the first 500 settings in order and marks them truncated when more match' {
        Mock Get-CIPPIntuneSettingSearch { 1..501 | ForEach-Object { New-SettingRow $_ } }

        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'password' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 500
        $Response.Body.Results[0].SettingId | Should -Be 'id-1'
        $Response.Body.Results[-1].SettingId | Should -Be 'id-500'
        $Response.Body.Metadata.Truncated | Should -BeTrue
    }

    It 'asks the search to keep no more than 500 settings' {
        $null = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'password' }) -TriggerMetadata $null

        Should -Invoke Get-CIPPIntuneSettingSearch -Times 1 -Exactly -ParameterFilter { $MaxResults -eq 500 }
    }

    It 'counts devices for the capped results only' {
        Mock Get-CIPPIntuneSettingSearch { 1..501 | ForEach-Object { New-SettingRow $_ } }

        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'password' }) -TriggerMetadata $null

        Should -Invoke Add-CIPPIntuneSettingDeviceCount -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' -and @($Results).Count -eq 500 }
        $Response.Body.Results[0].DeviceCount | Should -Be 7
    }

    It 'returns the settings with a warning log when devices cannot be counted' {
        Mock Add-CIPPIntuneSettingDeviceCount { throw 'table unavailable' }

        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'password' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*table unavailable*' }
    }

    It 'rejects <Name> before reading the cache' -ForEach @(
        @{ Name = 'AllTenants'; Query = @{ TenantFilter = 'AllTenants'; search = 'password' } }
        @{ Name = 'AllTenants in any case'; Query = @{ TenantFilter = 'alltenants'; search = 'password' } }
        @{ Name = 'a tenant group the router passed on as AllTenants'; Query = @{ TenantFilter = 'AllTenants'; tenantGroup = 'group-1'; search = 'password' } }
        @{ Name = 'AllTenants with a short search'; Query = @{ TenantFilter = 'AllTenants'; search = 'a' } }
        @{ Name = 'a tenant group'; Query = @{ TenantFilter = 'group:0f6c1e3a-4c8e-4d55-9a0b-2f4e6d7c8b9a'; search = 'password' } }
    ) {
        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request $Query) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*single tenant*'
        Should -Invoke Get-CIPPIntuneSettingSearch -Times 0 -Exactly
        Should -Invoke Add-CIPPIntuneSettingDeviceCount -Times 0 -Exactly
    }

    It 'is not marked for tenant groups, so the router refuses a tenantGroup request' {
        (Get-Help Invoke-ListIntuneSettingSearch).Functionality | Should -Be 'Entrypoint'
    }

    It 'rejects a missing tenant' {
        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ search = 'password' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 400
        Should -Invoke Get-CIPPIntuneSettingSearch -Times 0 -Exactly
    }

    It 'returns 500 with the error when the report fails' {
        Mock Get-CIPPIntuneSettingSearch { throw 'cache unavailable' }

        $Response = Invoke-ListIntuneSettingSearch -Request (New-Request @{ TenantFilter = 'contoso.onmicrosoft.com'; search = 'password' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'cache unavailable'
    }
}
