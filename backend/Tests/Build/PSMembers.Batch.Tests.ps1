# Pester tests for the one-call PSMembers helpers the audit log engine shapes each record with.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $script:Guid = '11111111-2222-3333-4444-555555555555'
    $script:Markers = [string[]]@('user_', 'tenant:')
}

Describe 'PSMembers.CopyExcept' {
    It 'copies the record less the named properties, case-insensitively, and leaves the source alone' {
        $Source = [CIPP.CippJson]::ConvertFromJson('{"Id":"1","ExtendedProperties":[1],"Parameters":[2],"Workload":"Exchange"}')
        $Copy = [CIPP.PSMembers]::CopyExcept($Source, [string[]]@('ExtendedProperties', 'parameters'))
        $Copy.PSObject.Properties.Name | Should -Be @('Id', 'Workload')
        $Source.PSObject.Properties.Name | Should -Be @('Id', 'ExtendedProperties', 'Parameters', 'Workload')
        $Copy.Workload = 'Changed'
        $Source.Workload | Should -Be 'Exchange'
    }
}

Describe 'PSMembers.AddNoteProperties' {
    It 'adds in dictionary order and, without force, keeps an existing value as Add-Member does' {
        $Members = [ordered]@{ Kept = 'new'; Added = $null; Second = 2 }
        $Expected = [pscustomobject]@{ Kept = 'old' }
        $Expected | Add-Member -NotePropertyMembers $Members -ErrorAction SilentlyContinue
        $Actual = [pscustomobject]@{ Kept = 'old' }
        [CIPP.PSMembers]::AddNoteProperties($Actual, $Members, $false)
        $Actual.PSObject.Properties.Name | Should -Be $Expected.PSObject.Properties.Name
        $Actual.Kept | Should -Be 'old'
    }

    It 'with force replaces an existing value and moves it to the end, as Add-Member -Force does' {
        $Members = [ordered]@{ A = 'new'; C = 3 }
        $Expected = [pscustomobject]@{ A = 1; B = 2 }
        $Expected | Add-Member -NotePropertyMembers $Members -Force
        $Actual = [pscustomobject]@{ A = 1; B = 2 }
        [CIPP.PSMembers]::AddNoteProperties($Actual, $Members, $true)
        $Actual.PSObject.Properties.Name | Should -Be $Expected.PSObject.Properties.Name
        $Actual.A | Should -Be 'new'
    }

    It 'skips names Add-Member refuses, such as a method or a reserved name, and keeps going' {
        $Actual = [pscustomobject]@{ A = 1 }
        [CIPP.PSMembers]::AddNoteProperties($Actual, [ordered]@{ ToString = 'x'; psobject = 'y'; B = 2 }, $false)
        $Actual.PSObject.Properties.Name | Should -Be @('A', 'B')
    }
}

Describe 'PSMembers.MapStringProperties' {
    It 'adds prefix + name holding the field of a dictionary entry, or the whole entry when the field is empty' {
        $Group = @{ id = 'g'; displayName = 'Admins' }
        $Lookups = [System.Collections.IDictionary[]]@(@{ $script:Guid = @{ userPrincipalName = 'u@contoso.com' } }, @{ 'aaaaaaaa-2222-3333-4444-555555555555' = $Group })
        $Record = [pscustomobject]@{ UserKey = $script:Guid; Target = 'aaaaaaaa-2222-3333-4444-555555555555'; Workload = 'AzureActiveDirectory' }
        $Left = @([CIPP.PSMembers]::MapStringProperties($Record, $Lookups, [string[]]@('userPrincipalName', ''), 'CIPP', $script:Markers))
        $Left | Should -HaveCount 0
        $Record.PSObject.Properties.Name | Should -Be @('UserKey', 'Target', 'Workload', 'CIPPUserKey', 'CIPPTarget')
        $Record.CIPPUserKey | Should -Be 'u@contoso.com'
        [object]::ReferenceEquals($Record.CIPPTarget, $Group) | Should -BeTrue
    }

    It 'reads the field off an object entry, and gives null when the entry lacks it' {
        $Lookups = [System.Collections.IDictionary[]]@(@{ $script:Guid = [pscustomobject]@{ userPrincipalName = 'obj@contoso.com' }; 'bbbbbbbb-2222-3333-4444-555555555555' = [pscustomobject]@{ id = 'x' } })
        $Record = [pscustomobject]@{ UserKey = $script:Guid; ObjectId = 'bbbbbbbb-2222-3333-4444-555555555555' }
        $null = [CIPP.PSMembers]::MapStringProperties($Record, $Lookups, [string[]]@('userPrincipalName'), 'CIPP', $script:Markers)
        $Record.CIPPUserKey | Should -Be 'obj@contoso.com'
        $Record.PSObject.Properties.Name | Should -Contain 'CIPPObjectId'
        $Record.CIPPObjectId | Should -BeNullOrEmpty
    }

    It 'replaces an existing property of the mapped name and appends it, with no prefix' {
        $Record = [pscustomobject]@{ UserKey = $script:Guid; Other = 1 }
        $null = [CIPP.PSMembers]::MapStringProperties($Record, [System.Collections.IDictionary[]]@(, @{ $script:Guid = @{ userPrincipalName = 'u@contoso.com' } }), [string[]]@('userPrincipalName'), '', $script:Markers)
        $Record.PSObject.Properties.Name | Should -Be @('Other', 'UserKey')
        $Record.UserKey | Should -Be 'u@contoso.com'
    }

    It 'hands back marker values untouched for the caller to map' {
        $Record = [pscustomobject]@{ UserId = 'user_0123@partner.onmicrosoft.com' }
        $Left = @([CIPP.PSMembers]::MapStringProperties($Record, [System.Collections.IDictionary[]]@(, @{}), [string[]]@('userPrincipalName'), 'CIPP', $script:Markers))
        $Left.Name | Should -Be @('UserId')
        $Left[0].LookupIndex | Should -Be -1
        $Record.PSObject.Properties.Name | Should -Be @('UserId')
    }
}

Describe 'PSMembers.CollectStringValues' {
    It 'collects the own string values the pattern matches, and nothing nested' {
        $Set = [System.Collections.Generic.HashSet[string]]::new()
        $Record = [pscustomobject]@{ A = $script:Guid; B = 'not-a-guid'; C = 36; D = [pscustomobject]@{ E = 'cccccccc-2222-3333-4444-555555555555' } }
        [CIPP.PSMembers]::CollectStringValues($Record, [regex]'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', $Set)
        @($Set) | Should -Be @($script:Guid)
    }
}
