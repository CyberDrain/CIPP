# Pester tests for Set-CIPPGroupLicense.
#
# Every group-license path in the product (Edit Group, Add Group, group templates via the standard,
# Remove-CIPPGroup) funnels through this helper, which builds the body for
# POST /groups/{id}/assignLicense. The body shape Graph wants is
#   addLicenses: [{ skuId, disabledPlans: [servicePlanId, ...] }], removeLicenses: [skuId, ...]
# and the plan ids must belong to that SKU, so the per-SKU grouping done here is the thing worth pinning.
#
# -DisabledPlans arrives in two shapes: the JSON request body (a PSCustomObject keyed by skuId whose
# values are autocomplete options { value = planId }) from the forms, or a hashtable with bare ids
# from scripts. Older callers (Remove-CIPPGroup, templates saved before the feature) pass nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPGroupLicense.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPGroupLicense.ps1 under Modules/' }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { param($API, $tenant, $Headers, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    $script:SkuA = '6fd2c87f-b296-42f0-b197-1e91e994b900'
    $script:SkuB = '05e9a617-0261-4cee-bb44-138d3ef5d965'
    $script:PlanOneDrive = 'e95bec33-7c88-4a70-8e19-b10bd9d0c014'
    $script:PlanTeams = '57ff2da0-773e-42df-b2af-ffb7a2317929'

    # The body is posted as compressed JSON; parse it back so assertions read like the Graph contract.
    function Get-PostedBody {
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/groups/group-guid/assignLicense' -and $type -eq 'POST' }
        $script:PostedBody | ConvertFrom-Json
    }
}

Describe 'Set-CIPPGroupLicense' {
    BeforeEach {
        Mock Write-LogMessage { }
        $script:PostedBody = $null
        Mock New-GraphPOSTRequest { $script:PostedBody = $body }
        Mock New-GraphGetRequest { }
    }

    Context 'disabledPlans grouping' {
        It 'puts each SKU''s plans under that SKU and leaves the others empty' {
            $DisabledPlans = [pscustomobject]@{
                $script:SkuA = @(
                    [pscustomobject]@{ label = 'OneDrive'; value = $script:PlanOneDrive }
                    [pscustomobject]@{ label = 'Teams'; value = $script:PlanTeams }
                )
            }

            $null = Set-CIPPGroupLicense -GroupId 'group-guid' -AddLicenses @($script:SkuA, $script:SkuB) -DisabledPlans $DisabledPlans -TenantFilter 'contoso.com'

            $Body = Get-PostedBody
            $Body.addLicenses.Count | Should -Be 2
            $A = $Body.addLicenses | Where-Object skuId -EQ $script:SkuA
            $B = $Body.addLicenses | Where-Object skuId -EQ $script:SkuB
            @($A.disabledPlans) | Should -Be @($script:PlanOneDrive, $script:PlanTeams)
            @($B.disabledPlans).Count | Should -Be 0
            @($Body.removeLicenses).Count | Should -Be 0
        }

        It 'accepts a hashtable of bare plan ids' {
            $null = Set-CIPPGroupLicense -GroupId 'group-guid' -AddLicenses @($script:SkuA) -DisabledPlans @{ $script:SkuA = @($script:PlanTeams) } -TenantFilter 'contoso.com'

            $Body = Get-PostedBody
            @($Body.addLicenses[0].disabledPlans) | Should -Be @($script:PlanTeams)
        }

        It 'matches the skuId key case-insensitively' {
            $DisabledPlans = [pscustomobject]@{ ($script:SkuA.ToUpperInvariant()) = @([pscustomobject]@{ value = $script:PlanTeams }) }

            $null = Set-CIPPGroupLicense -GroupId 'group-guid' -AddLicenses @($script:SkuA) -DisabledPlans $DisabledPlans -TenantFilter 'contoso.com'

            $Body = Get-PostedBody
            @($Body.addLicenses[0].disabledPlans) | Should -Be @($script:PlanTeams)
        }

        It 'drops blank plan entries' {
            $null = Set-CIPPGroupLicense -GroupId 'group-guid' -AddLicenses @($script:SkuA) -DisabledPlans @{ $script:SkuA = @('', $null, $script:PlanTeams) } -TenantFilter 'contoso.com'

            $Body = Get-PostedBody
            @($Body.addLicenses[0].disabledPlans) | Should -Be @($script:PlanTeams)
        }

        It 'sends an empty disabledPlans list when no map is passed (legacy callers)' {
            $null = Set-CIPPGroupLicense -GroupId 'group-guid' -AddLicenses @($script:SkuA) -RemoveLicenses @($script:SkuB) -TenantFilter 'contoso.com'

            $Body = Get-PostedBody
            $Body.addLicenses[0].skuId | Should -Be $script:SkuA
            @($Body.addLicenses[0].disabledPlans).Count | Should -Be 0
            @($Body.removeLicenses) | Should -Be @($script:SkuB)
        }

        It 'reports how many plans were disabled per SKU' {
            $Results = @(Set-CIPPGroupLicense -GroupId 'group-guid' -GroupName 'Sales' -AddLicenses @($script:SkuA, $script:SkuB) -DisabledPlans @{ $script:SkuA = @($script:PlanOneDrive, $script:PlanTeams) } -TenantFilter 'contoso.com')

            $Results.Count | Should -Be 1
            $Results[0] | Should -BeLike "Assigned licenses to group Sales. Added: $($script:SkuA) (2 service plans disabled), $($script:SkuB).*"
        }
    }

    Context 'nothing to do' {
        It 'does not call Graph when both lists are empty' {
            $Results = @(Set-CIPPGroupLicense -GroupId 'group-guid' -GroupName 'Sales' -DisabledPlans @{ $script:SkuA = @($script:PlanTeams) } -TenantFilter 'contoso.com')

            $Results | Should -Be @('No license changes required for group Sales.')
            Should -Invoke New-GraphPOSTRequest -Times 0
        }
    }

    Context 'errors' {
        It 'rethrows a Graph failure with the group name' {
            Mock New-GraphPOSTRequest { throw 'License assignment failed' }

            { Set-CIPPGroupLicense -GroupId 'group-guid' -GroupName 'Sales' -AddLicenses @($script:SkuA) -TenantFilter 'contoso.com' } |
                Should -Throw '*Failed to update licenses for group Sales*'
            Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Error' }
        }
    }
}
