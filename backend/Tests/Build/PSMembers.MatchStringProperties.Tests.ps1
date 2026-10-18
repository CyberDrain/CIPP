# Pester tests for CIPP.PSMembers.MatchStringProperties - the per-record property scan behind audit log GUID mapping.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $script:Markers = [string[]]@('user_', 'tenant:')
    function Find-Match($Record, [object[]]$Lookups) {
        @([CIPP.PSMembers]::MatchStringProperties($Record, [System.Collections.IDictionary[]]@($Lookups), $script:Markers))
    }
}

Describe 'PSMembers.MatchStringProperties' {
    It 'returns the first lookup holding a 36-character value' {
        $Guid = '11111111-2222-3333-4444-555555555555'
        $Record = [pscustomobject]@{ UserKey = $Guid }
        $Found = Find-Match $Record @(@{}, @{ $Guid = 'group' }, @{ $Guid = 'device' })
        $Found | Should -HaveCount 1
        $Found[0].Name | Should -Be 'UserKey'
        $Found[0].LookupIndex | Should -Be 1
    }

    It 'matches a PowerShell hashtable key regardless of case' {
        $Record = [pscustomobject]@{ ObjectId = 'AAAAAAAA-2222-3333-4444-555555555555' }
        (Find-Match $Record @(, @{ 'aaaaaaaa-2222-3333-4444-555555555555' = 'user' }))[0].LookupIndex | Should -Be 0
    }

    It 'skips a 36-character value no lookup holds, without checking it for markers' {
        $Record = [pscustomobject]@{ Id = 'user_aaa-2222-3333-4444-555555555555' }
        Find-Match $Record @(, @{}) | Should -HaveCount 0
    }

    It 'returns a value of any other length that contains a marker, ordinally' {
        $Record = [pscustomobject]@{ UserId = 'contoso.onmicrosoft.com\tenant: x, object: y'; Other = 'USER_upper@contoso.onmicrosoft.com'; Upn = 'user_0123@x.onmicrosoft.com' }
        $Found = Find-Match $Record @(, @{})
        $Found.Name | Should -Be @('UserId', 'Upn')
        $Found.LookupIndex | Should -Be @(-1, -1)
    }

    It 'ignores values that are not strings and empty strings' {
        $Record = [pscustomobject]@{ Count = 36; Flag = $true; Empty = ''; Nested = [pscustomobject]@{ Id = '11111111-2222-3333-4444-555555555555' } }
        Find-Match $Record @(, @{ '11111111-2222-3333-4444-555555555555' = 'x' }) | Should -HaveCount 0
    }

    It 'reads the properties of a record parsed by CippJson' {
        $Record = [CIPP.CippJson]::ConvertFromJson('{"UserKey":"11111111-2222-3333-4444-555555555555","Workload":"Exchange"}')
        (Find-Match $Record @(, @{ '11111111-2222-3333-4444-555555555555' = 'user' }))[0].Name | Should -Be 'UserKey'
    }
}
