# Invoke-ListUserDevices: a failed device read must be an error, not an empty device list.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphBulkResultByID.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ListUserDevices.ps1') -Raw)))

    function New-Request ([hashtable]$Query) { [pscustomobject]@{ Query = [pscustomobject]$Query; Headers = @{} } }
}

Describe 'Invoke-ListUserDevices' {
    It 'lists the owned devices with their Intune id' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/managedDevices' } { [pscustomobject]@{ id = 'epm-1'; azureADDeviceId = 'dev-1' } }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/ownedDevices*' } { [pscustomobject]@{ id = 'obj-1'; deviceId = 'dev-1'; displayName = 'LAPTOP-1' } }

        $Response = Invoke-ListUserDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; UserID = 'u1' })

        $Response.StatusCode | Should -Be 200
        $Response.Body[0].displayName | Should -Be 'LAPTOP-1'
        $Response.Body[0].EPMID | Should -Be 'epm-1'
    }

    It 'returns the error with a failure status when Graph fails' {
        Mock New-GraphGetRequest { throw 'Insufficient privileges to complete the operation.' }

        $Response = Invoke-ListUserDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; UserID = 'u1' })

        $Response.StatusCode | Should -Be 500
        $Response.Body | Should -Be @('Insufficient privileges to complete the operation.')
    }
}
