# Pester tests for Test-DeltaQueryConditions
# The scheduler form saves conditions as Trigger.DeltaConditions ({Property, Operator: {label, value}, Value}),
# but only Trigger.Conditions, which nothing writes, was read, so every saved condition was ignored and any
# change fired the task. Also pins the Deleted event: Graph marks a soft delete @removed.reason 'changed'
# and a permanent delete 'deleted', and only 'changed' was accepted.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in 'Test-DeltaQueryConditions', 'Test-CIPPConditionFilter', 'ConvertTo-CIPPScriptBlockValue') {
        $Path = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File | Select-Object -First 1 -ExpandProperty FullName
        if (-not $Path) { throw "Could not locate $Name.ps1 under Modules/" }
        . $Path
    }
    function New-GraphBulkRequest { param($Requests, $tenantid) }

    $script:Since = [datetime]::UtcNow.AddMinutes(-15)
    $script:Users = @{
        value = @(
            [pscustomobject]@{ id = 'u1'; displayName = 'Alice Admin'; createdDateTime = [datetime]::UtcNow.AddDays(-5) }
            [pscustomobject]@{ id = 'u2'; displayName = 'Bob'; createdDateTime = [datetime]::UtcNow.AddDays(-5) }
        )
    }
    function Invoke-Test {
        param($Trigger, $Query = $script:Users)
        Test-DeltaQueryConditions -Query $Query -Trigger $Trigger -TenantFilter 'contoso.com' -LastTrigger $script:Since
    }
}

Describe 'Test-DeltaQueryConditions' {
    BeforeEach {
        Mock -CommandName New-GraphBulkRequest -MockWith { }
    }

    Context 'Conditions saved by the scheduler form (DeltaConditions)' {
        It 'applies them as an object array' {
            $Trigger = [pscustomobject]@{
                EventType       = 'updated'
                UseConditions   = $true
                DeltaConditions = @([pscustomobject]@{ Property = 'displayName'; Operator = [pscustomobject]@{ label = 'Like'; value = 'like' }; Value = '*admin*' })
            }

            $Result = Invoke-Test -Trigger $Trigger

            $Result.ConditionsMet | Should -BeTrue
            @($Result.MatchedData).id | Should -Be @('u1')
        }

        It 'applies them from a stored JSON trigger' {
            $Trigger = '{"EventType":{"value":"updated"},"UseConditions":true,"DeltaConditions":[{"Property":"displayName","Operator":{"label":"Equals to","value":"eq"},"Value":"Nobody"}]}' | ConvertFrom-Json

            $Result = Invoke-Test -Trigger $Trigger

            $Result.ConditionsMet | Should -BeFalse
            $Result.MatchedItems | Should -Be 0
        }

        It 'ANDs several conditions' {
            $Trigger = [pscustomobject]@{
                EventType       = 'updated'
                UseConditions   = $true
                DeltaConditions = @(
                    [pscustomobject]@{ Property = 'displayName'; Operator = [pscustomobject]@{ value = 'like' }; Value = '*' }
                    [pscustomobject]@{ Property = 'id'; Operator = [pscustomobject]@{ value = 'ne' }; Value = 'u1' }
                )
            }

            @((Invoke-Test -Trigger $Trigger).MatchedData).id | Should -Be @('u2')
        }

        It 'ignores them when UseConditions is off' {
            $Trigger = [pscustomobject]@{
                EventType       = 'updated'
                UseConditions   = $false
                DeltaConditions = @([pscustomobject]@{ Property = 'displayName'; Operator = [pscustomobject]@{ value = 'eq' }; Value = 'Nobody' })
            }

            (Invoke-Test -Trigger $Trigger).MatchedItems | Should -Be 2
        }
    }

    Context 'Deleted event' {
        BeforeAll {
            $script:Removed = @{
                value = @(
                    [pscustomobject]@{ id = 'soft'; '@removed' = [pscustomobject]@{ reason = 'changed' } }
                    [pscustomobject]@{ id = 'hard'; '@removed' = [pscustomobject]@{ reason = 'deleted' } }
                    [pscustomobject]@{ id = 'live'; displayName = 'Still here' }
                )
            }
        }

        It 'matches a permanent delete on a resource without a recycle bin' {
            $Result = Invoke-Test -Query $script:Removed -Trigger ([pscustomobject]@{ EventType = 'deleted'; DeltaResource = 'devices' })

            @($Result.MatchedData).id | Should -Be @('soft', 'hard')
        }

        It 'looks up only the soft-deleted items in deletedItems' {
            $null = Invoke-Test -Query $script:Removed -Trigger ([pscustomobject]@{ EventType = 'deleted'; DeltaResource = 'devices' })

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).id -join ',' -eq 'soft' }
        }

        It 'does not fire a second time when a soft-deleted <Resource> is purged' -ForEach @(
            @{ Resource = 'users' }, @{ Resource = 'groups' }, @{ Resource = 'applications' }, @{ Resource = 'servicePrincipals' }
        ) {
            $Result = Invoke-Test -Query $script:Removed -Trigger ([pscustomobject]@{ EventType = 'deleted'; DeltaResource = [pscustomobject]@{ value = $Resource } })

            @($Result.MatchedData).id | Should -Be @('soft')
        }
    }
}
