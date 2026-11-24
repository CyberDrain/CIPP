# Set-CIPPDBCacheRoles caches directory roles with their members. A failed or truncated member read must not
# overwrite the cached role with an empty member list.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheRoles.ps1')
}

Describe 'Set-CIPPDBCacheRoles' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'r1'; displayName = 'Global Administrator'; roleTemplateId = 't1' }
            [pscustomobject]@{ id = 'r2'; displayName = 'Helpdesk Administrator'; roleTemplateId = 't2' }
        }
    }

    It 'attaches each role its own members' {
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = 'r2'; status = 200; body = [pscustomobject]@{ value = @() } }
            [pscustomobject]@{ id = 'r1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u1' }, [pscustomobject]@{ id = 'u2' }) } }
        }

        Set-CIPPDBCacheRoles -TenantFilter 'contoso.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'Roles' -and $Data[0].id -eq 'r1' -and $Data[0].memberCount -eq 2 -and $Data[1].memberCount -eq 0
        }
    }

    It 'writes nothing when a member read fails' {
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = 'r1'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }
            [pscustomobject]@{ id = 'r2'; status = 200; body = [pscustomobject]@{ value = @() } }
        }

        Set-CIPPDBCacheRoles -TenantFilter 'contoso.com'

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' -and $message -like '*Insufficient privileges*' }
    }

    It 'writes nothing when a member list is truncated' {
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = 'r1'; status = 200; PagingIncomplete = $true; PagingError = 'continuation page returned 429'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'u1' }) } }
            [pscustomobject]@{ id = 'r2'; status = 200; body = [pscustomobject]@{ value = @() } }
        }

        Set-CIPPDBCacheRoles -TenantFilter 'contoso.com'

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }
}
