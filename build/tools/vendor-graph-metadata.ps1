#Requires -Version 7.0

# Vendors the Microsoft Graph CSDL ($metadata) for v1.0 and beta into
# backend/Config/graph-metadata.
#
# Why the CSDL and not the OpenAPI YAML: Microsoft generates both the published OpenAPI
# documents and every Graph SDK from this CSDL, so it is the upstream source rather than
# a rendering of it - and it is far smaller (9.8 MB against 107 MB of YAML for the same
# two versions).
#
# Why vendored rather than fetched during the build: the build must stay hermetic and
# reproducible, and this repo pins its package registries for the same reason. Refreshing
# is a deliberate act with a reviewable diff, not something that happens silently on a
# rebuild. The manifest records when each file was taken and its SHA-256 so a change can
# be told apart from a corruption.
#
# Run this to refresh:  pwsh build/tools/vendor-graph-metadata.ps1

[CmdletBinding()]
param(
    [string]$OutputPath = "$PSScriptRoot/../../backend/Config/graph-metadata",
    # Verify the vendored copies match upstream without writing anything. Intended for a
    # scheduled job that opens a PR when Graph moves, rather than for the build.
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$Versions = @(
    @{ Name = 'v1.0'; Uri = 'https://graph.microsoft.com/v1.0/$metadata' }
    @{ Name = 'beta'; Uri = 'https://graph.microsoft.com/beta/$metadata' }
)

if (-not (Test-Path $OutputPath)) { $null = New-Item -ItemType Directory -Path $OutputPath -Force }

$Manifest = [ordered]@{
    source      = 'Microsoft Graph CSDL ($metadata)'
    description = 'Vendored so the OpenAPI generator and the runtime schema lookup can describe Graph responses without a network call. Refresh with build/tools/vendor-graph-metadata.ps1.'
    retrieved   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    versions    = [ordered]@{}
}

$Drift = $false

foreach ($Version in $Versions) {
    $Target = Join-Path $OutputPath "$($Version.Name).xml"
    Write-Host "Fetching $($Version.Uri)"

    # PowerShell 7 hands back a string for a text content type and a byte[] otherwise, and
    # which one Graph triggers is not worth depending on.
    $Response = Invoke-WebRequest -Uri $Version.Uri -Headers @{ Accept = 'application/xml' } -TimeoutSec 300
    $Content = if ($Response.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($Response.Content)
    } else {
        [string]$Response.Content
    }

    # A truncated or error response would otherwise be vendored silently.
    if ($Content -notmatch '<edmx:Edmx' -or $Content -notmatch 'EntityContainer') {
        throw "Response for $($Version.Name) does not look like a CSDL document."
    }

    $Hash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Content))
    ).Replace('-', '').ToLowerInvariant()

    if ($Check) {
        if (-not (Test-Path $Target)) {
            Write-Host "  MISSING: $($Version.Name).xml is not vendored" -ForegroundColor Red
            $Drift = $true
            continue
        }
        $Existing = [System.IO.File]::ReadAllText($Target)
        $ExistingHash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Existing))
        ).Replace('-', '').ToLowerInvariant()
        if ($ExistingHash -ne $Hash) {
            Write-Host "  DRIFT: $($Version.Name) has changed upstream" -ForegroundColor Yellow
            $Drift = $true
        } else {
            Write-Host "  up to date: $($Version.Name)"
        }
        continue
    }

    [System.IO.File]::WriteAllText($Target, $Content, (New-Object System.Text.UTF8Encoding($false)))
    $SizeMb = [math]::Round($Content.Length / 1MB, 1)
    Write-Host "  wrote $($Version.Name).xml ($SizeMb MB)"

    $Manifest.versions[$Version.Name] = [ordered]@{
        uri    = $Version.Uri
        file   = "$($Version.Name).xml"
        bytes  = $Content.Length
        sha256 = $Hash
    }
}

if ($Check) {
    if ($Drift) { Write-Host 'Vendored Graph metadata differs from upstream.'; exit 1 }
    Write-Host 'Vendored Graph metadata matches upstream.'
    exit 0
}

$ManifestPath = Join-Path $OutputPath 'manifest.json'
$Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $ManifestPath -Encoding utf8
Write-Host "Wrote $ManifestPath"

& "$PSScriptRoot/Update-IntuneGraphSchema.ps1" -MetadataPath (Join-Path $OutputPath 'beta.xml')
