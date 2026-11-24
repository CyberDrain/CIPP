# Invoke-ListCompliancePolicies (live path) reads the policies and the tenant's groups in one batch. A failed policies read is an
# error, not an empty list; a failed group read still shows group-targeted assignments, by group id.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphBulkResultByID.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListCompliancePolicies.ps1') -Raw)))

    function New-Request ([hashtable]$Query) { [pscustomobject]@{ Query = [pscustomobject]$Query; Headers = @{} } }
}

Describe 'Invoke-ListCompliancePolicies' {
    BeforeEach {
        $script:Item = [pscustomobject]@{
            id            = 'item-1'
            displayName   = 'Item One'
            assignments   = @(
                [pscustomobject]@{ target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } }
                [pscustomobject]@{ target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g2' } }
            )
        }
        $script:GroupsResponse = [pscustomobject]@{ id = 'Groups'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g1'; displayName = 'Sales' }, [pscustomobject]@{ id = 'g2'; displayName = 'Kiosks' }) } }
        $script:ItemResponse = [pscustomobject]@{ id = 'CompliancePolicies'; status = 200; body = [pscustomobject]@{ value = @($script:Item) } }
        Mock New-GraphBulkRequest { $script:GroupsResponse; $script:ItemResponse }
    }

    It 'resolves group assignments to their names' {
        $Response = Invoke-ListCompliancePolicies -Request (New-Request @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 200
        $Response.Body[0].PolicyAssignment | Should -Be 'Sales'
        $Response.Body[0].PolicyExclude | Should -Be 'Kiosks'
    }

    It 'returns an error, not an empty list, when the policies read fails' {
        $script:ItemResponse = [pscustomobject]@{ id = 'CompliancePolicies'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }

        $Response = Invoke-ListCompliancePolicies -Request (New-Request @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 500
        @($Response.Body)[0] | Should -BeLike '*Insufficient privileges*'
    }

    It 'shows the group id when the group read fails instead of dropping the assignment' {
        $script:GroupsResponse = [pscustomobject]@{ id = 'Groups'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }

        $Response = Invoke-ListCompliancePolicies -Request (New-Request @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 200
        $Response.Body[0].PolicyAssignment | Should -Be 'g1'
        $Response.Body[0].PolicyExclude | Should -Be 'g2'
    }
}
