# Pester tests for Invoke-ExecGeoIPLookup: an audit log address with a port is looked up without it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }
    function Get-CIPPGeoIPLocation { param($IP) }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ExecGeoIPLookup.ps1' -File)[0].FullName
    function Invoke-Lookup($IP) { Invoke-ExecGeoIPLookup -Request ([pscustomobject]@{ Query = [pscustomobject]@{ IP = $IP } }) -TriggerMetadata $null }
}

Describe 'Invoke-ExecGeoIPLookup' {
    BeforeEach { Mock Get-CIPPGeoIPLocation { [pscustomobject]@{ countryCode = 'AU' } } }

    It 'looks up <Given> as <Looked>' -ForEach @(
        @{ Given = '203.0.113.10:13892'; Looked = '203.0.113.10' }
        @{ Given = '203.0.113.10'; Looked = '203.0.113.10' }
        @{ Given = '[2001:db8::1]:443'; Looked = '2001:db8::1' }
        @{ Given = '2001:db8::1'; Looked = '2001:db8::1' }
    ) {
        (Invoke-Lookup $Given).StatusCode | Should -Be 200
        Should -Invoke Get-CIPPGeoIPLocation -Times 1 -Exactly -ParameterFilter { $IP -eq $Looked }
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'no address'; Given = '' }
        @{ Case = 'something that is not an address'; Given = "1.2.3.4' or true" }
    ) {
        (Invoke-Lookup $Given).StatusCode | Should -Be 400
        Should -Invoke Get-CIPPGeoIPLocation -Times 0 -Exactly
    }

    It 'returns 500 when the lookup fails' {
        Mock Get-CIPPGeoIPLocation { throw 'Could not get location for 203.0.113.10' }
        (Invoke-Lookup '203.0.113.10:1').StatusCode | Should -Be 500
    }
}
