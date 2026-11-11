BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-TokenCacheDiagnostics { [CIPP.CIPPTokenCache]::GetDiagnostics() | ConvertFrom-Json }
}

Describe 'CIPPTokenCache bounds' {
    BeforeEach { $null = [CIPP.CIPPTokenCache]::Clear() }

    It 'drops expired entries that are never looked up again' {
        $Expired = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 10
        foreach ($i in 1..2000) { [CIPP.CIPPTokenCache]::Store("tenant$i|scope|app||client_credentials|failed", 'AADSTS53003', $Expired) }
        (Get-TokenCacheDiagnostics).Entries | Should -BeLessOrEqual 256
    }

    It 'never holds more than 10000 entries' {
        $Live = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600
        foreach ($i in 1..12000) { [CIPP.CIPPTokenCache]::Store("tenant$i|scope|app||client_credentials", '{}', $Live + $i) }
        (Get-TokenCacheDiagnostics).Entries | Should -BeLessOrEqual 10000
        [CIPP.CIPPTokenCache]::Lookup('tenant12000|scope|app||client_credentials', 120).Found | Should -BeTrue
    }

    It 'keeps live entries when sweeping expired ones' {
        $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        [CIPP.CIPPTokenCache]::Store('live|scope|app||client_credentials', '{"access_token":"x"}', $Now + 3600)
        foreach ($i in 1..600) { [CIPP.CIPPTokenCache]::Store("dead$i", 'x', $Now - 10) }
        [CIPP.CIPPTokenCache]::Lookup('live|scope|app||client_credentials', 120).TokenPayloadJson | Should -Be '{"access_token":"x"}'
    }
}
