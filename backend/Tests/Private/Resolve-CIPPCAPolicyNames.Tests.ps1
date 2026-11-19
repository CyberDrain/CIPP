# Pester tests for Resolve-CIPPCAPolicyNames
# Graph only takes object IDs in a CA policy's location, user and group conditions; a display name
# fails the whole write (e.g. "1040: NamedLocation with id <name> does not exist in the directory").
# These pin that names resolve to the tenant's IDs, that keywords and GUIDs pass through untouched,
# that a name matching nothing stops with the value named, and that the tenant is only queried
# when there is a name to resolve.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAUserNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAGroupNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Resolve-CIPPCAPolicyNames.ps1')

    $script:LocationId = '11111111-1111-1111-1111-111111111111'
    $script:GroupId = '22222222-2222-2222-2222-222222222222'
    $script:UserId = '33333333-3333-3333-3333-333333333333'
    $script:OtherId = '44444444-4444-4444-4444-444444444444'

    function New-GraphGETRequest {
        [CmdletBinding()] param($uri, $tenantid, $asApp)
        $script:GraphGets.Add($uri)
        @([pscustomobject]@{ id = $script:LocationId; displayName = 'CT-CA-Anthropic' })
    }
    function New-GraphBulkRequest {
        [CmdletBinding()] param($Requests, $tenantid, $asapp)
        $script:BulkRequests.Add(@($Requests.id))
        @(
            [pscustomobject]@{ id = 'users'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:UserId; displayName = 'Break Glass' }) } }
            [pscustomobject]@{ id = 'groups'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:GroupId; displayName = 'CA-Exclude' }) } }
        )
    }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    function New-Policy ([hashtable]$Locations, [hashtable]$Users) {
        [pscustomobject]@{
            displayName = 'CA100'
            conditions  = [pscustomobject]@{
                locations = if ($Locations) { [pscustomobject]$Locations }
                users     = [pscustomobject]($Users ?? @{ includeUsers = @('All') })
            }
        }
    }
}

Describe 'Resolve-CIPPCAPolicyNames' {
    BeforeEach {
        $script:GraphGets = [System.Collections.Generic.List[string]]::new()
        $script:BulkRequests = [System.Collections.Generic.List[object]]::new()
    }

    Context 'named locations' {
        It 'replaces a location name with the tenant location id' {
            $Policy = New-Policy -Locations @{ includeLocations = @('All'); excludeLocations = @('CT-CA-Anthropic') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:LocationId)
        }

        It 'passes All, AllTrusted and GUIDs through unchanged, alongside a resolved name' {
            $Policy = New-Policy -Locations @{ includeLocations = @('All'); excludeLocations = @('AllTrusted', $script:OtherId, 'CT-CA-Anthropic') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.locations.includeLocations) | Should -Be @('All')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @('AllTrusted', $script:OtherId, $script:LocationId)
        }

        It 'does not query the tenant when every location is already an id or keyword' {
            $Policy = New-Policy -Locations @{ includeLocations = @('All'); excludeLocations = @('AllTrusted', $script:OtherId) }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            $script:GraphGets.Count | Should -Be 0
            $script:BulkRequests.Count | Should -Be 0
        }

        It 'uses supplied named locations instead of fetching them' {
            $Policy = New-Policy -Locations @{ includeLocations = @('Head Office') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' -NamedLocations @([pscustomobject]@{ id = $script:OtherId; displayName = 'Head Office' })
            @($Policy.conditions.locations.includeLocations) | Should -Be @($script:OtherId)
            $script:GraphGets.Count | Should -Be 0
        }

        It 'matches the display name exactly, not as a pattern' {
            $Policy = New-Policy -Locations @{ excludeLocations = @('CT-CA-*') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }

        It 'throws a not-found error naming a location the tenant does not have' {
            $Policy = New-Policy -Locations @{ excludeLocations = @('Nowhere') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Named location 'Nowhere' used by policy 'CA100' was not found in contoso.com*"
        }

        It 'leaves users and groups alone with -LocationsOnly' {
            $Policy = New-Policy -Locations @{ excludeLocations = @('CT-CA-Anthropic') } -Users @{ excludeGroups = @('CA-Exclude') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' -LocationsOnly
            @($Policy.conditions.users.excludeGroups) | Should -Be @('CA-Exclude')
            $script:BulkRequests.Count | Should -Be 0
        }
    }

    Context 'users and groups' {
        It 'replaces group and user names with their ids' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeUsers = @('Break Glass'); excludeGroups = @('CA-Exclude', $script:OtherId) }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.users.includeUsers) | Should -Be @('All')
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId)
            @($Policy.conditions.users.excludeGroups) | Should -Be @($script:GroupId, $script:OtherId)
        }

        It 'passes user keywords through when they sit next to a name' {
            $Policy = New-Policy -Users @{ excludeUsers = @('GuestsOrExternalUsers', 'Break Glass') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.users.excludeUsers) | Should -Be @('GuestsOrExternalUsers', $script:UserId)
        }

        It 'fetches only the directory objects it has names for' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeGroups = @('CA-Exclude') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            $script:BulkRequests.Count | Should -Be 1
            $script:BulkRequests[0] | Should -Be @('groups')
        }

        It 'does not query the directory when every assignment is an id or keyword' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeUsers = @($script:UserId); excludeGroups = @($script:GroupId) }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            $script:BulkRequests.Count | Should -Be 0
        }

        It 'throws a not-found error naming a group the tenant does not have, and creates nothing' {
            $Policy = New-Policy -Users @{ excludeGroups = @('No Such Group') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Group 'No Such Group' not found in tenant contoso.com. Create the group first*"
        }

        It 'throws a not-found error naming a user the tenant does not have' {
            $Policy = New-Policy -Users @{ excludeUsers = @('Nobody') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "User 'Nobody' not found in tenant contoso.com*"
        }
    }
}
