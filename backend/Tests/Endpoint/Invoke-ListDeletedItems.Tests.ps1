# Invoke-ListDeletedItems reads every deleted-object type in one batch. A type that fails must not be
# reported as "no deleted items" with a 200.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphBulkResultByID.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ListDeletedItems.ps1') -Raw)))

    function New-Request ([hashtable]$Query) { [pscustomobject]@{ Query = [pscustomobject]$Query; Headers = @{} } }
}

Describe 'Invoke-ListDeletedItems' {
    BeforeEach {
        Mock Write-LogMessage { }
        $script:FailTypes = @()
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                if ($Request.id -in $script:FailTypes) {
                    [pscustomobject]@{ id = $Request.id; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }
                } elseif ($Request.id -eq 'user') {
                    [pscustomobject]@{ id = 'user'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u1'; displayName = 'Deleted User' }) } }
                } else {
                    [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @() } }
                }
            }
        }
    }

    It 'returns the deleted objects with their type when every read succeeds' {
        $Response = Invoke-ListDeletedItems -Request (New-Request @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 200
        $Response.Body.id | Should -Be @('u1')
        $Response.Body[0].TargetType | Should -Be 'User'
    }

    It 'returns 207 with the readable rows when some types fail' {
        $script:FailTypes = @('group')

        $Response = Invoke-ListDeletedItems -Request (New-Request @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 207
        $Response.Body.id | Should -Be @('u1')
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*Group: Insufficient privileges*' }
    }

    It 'returns 500 with the errors when every type fails' {
        $script:FailTypes = @('administrativeUnit', 'application', 'externalUserProfile', 'pendingExternalUserProfile', 'user', 'group', 'servicePrincipal', 'certificateBasedAuthPki', 'certificateAuthorityDetail')

        $Response = Invoke-ListDeletedItems -Request (New-Request @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 500
        @($Response.Body)[0] | Should -BeLike 'Could not list deleted items:*User: Insufficient privileges*'
    }
}
