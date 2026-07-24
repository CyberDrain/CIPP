# Compile CIPP PowerShell modules for the local dev loop.
#
# Non-destructive: reads module source from the repo's backend/Modules and
# writes the compiled .psm1/.psd1 into a separate output dir (build/.devmodules
# by default). docker-compose-no-frontend.yml overlays each compiled module dir
# over the bind-mounted source, so the running Craft container imports the fast
# single-file modules instead of dot-sourcing Public/*.ps1 in every worker
# runspace at startup.
#
# Unlike build-single-module.ps1 (which deletes Public/Private/Classes in place
# for the Docker image build), this never mutates the source tree, so your git
# working tree stays clean.
#
# Uses the ModuleBuilder/Configuration/Metadata copies vendored under build/ —
# no global install required.
param(
    [string]   $SourceModules = "$PSScriptRoot\..\..\backend\Modules",
    [string]   $OutputModules = "$PSScriptRoot\..\.devmodules",
    [string[]] $Modules       = @('CIPPCore','CIPPHTTP','CIPPStandards','CIPPDB','CIPPAlerts','CIPPActivityTriggers','CippExtensions', 'CIPPTests')
)

$ErrorActionPreference = 'Stop'

$sourceModulesPath = (Resolve-Path $SourceModules).Path
$outputModulesPath = [System.IO.Path]::GetFullPath($OutputModules)
# repo/build — parent of tools/, holds the vendored ModuleBuilder etc.
$buildDir = (Get-Item $PSScriptRoot).Parent.FullName

# Prefer the vendored ModuleBuilder/Configuration/Metadata in build/ over any
# globally installed copy.
$sep = [System.IO.Path]::PathSeparator
if (($env:PSModulePath -split [regex]::Escape($sep)) -notcontains $buildDir) {
    $env:PSModulePath = "$buildDir$sep$env:PSModulePath"
}
Import-Module -Name Metadata      -RequiredVersion 1.5.7 -Force
Import-Module -Name Configuration -RequiredVersion 1.6.0 -Force
Import-Module -Name ModuleBuilder -RequiredVersion 3.1.8 -Force

New-Item -ItemType Directory -Path $outputModulesPath -Force | Out-Null

Write-Host "=== Compiling dev modules ===" -ForegroundColor Cyan
Write-Host "  Source: $sourceModulesPath"
Write-Host "  Output: $outputModulesPath"

# Push/Pop so this script never leaks the caller's working directory — callers
# (e.g. the docker tab) run `docker compose -f <relative>` right after us.
# build the tests module but keep the source files as well as the as cipp-api relies on the source files for traversal currently.
# So build tests but keep the source files as well as the compiled module in the dev environment.
Push-Location $sourceModulesPath
try {
foreach ($mod in $Modules) {
    $buildManifest = Join-Path $mod 'build.psd1'
    if (-not (Test-Path $buildManifest)) {
        Write-Host "  SKIP $mod (no build.psd1)" -ForegroundColor Yellow
        continue
    }

    Write-Host "  Building $mod ..." -NoNewline
    # Compile into a throwaway dir so the bind-mounted source is never touched.
    $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) "cipp-devbuild-$mod"
    Remove-Item $tmpOut -Recurse -Force -ErrorAction SilentlyContinue
    try {
        if ($mod -eq 'CIPPTests') {
            # Build the tests module but keep the source files as well as the compiled module in the dev environment.
            Build-Module -SourcePath $buildManifest -OutputDirectory $tmpOut -ErrorAction Stop | Out-Null
            Copy-Item (Join-Path $sourceModulesPath $mod) (Join-Path $outputModulesPath $mod) -Recurse -Force
        } else {
            Build-Module -SourcePath $buildManifest -OutputDirectory $tmpOut -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Host " FAILED: $_" -ForegroundColor Red
        continue
    }

    $dst = Join-Path $outputModulesPath $mod
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item (Join-Path $tmpOut "$mod\$mod.psm1") (Join-Path $dst "$mod.psm1") -Force
    Copy-Item (Join-Path $tmpOut "$mod\$mod.psd1") (Join-Path $dst "$mod.psd1") -Force

    # ModuleBuilder writes RootModule = '.\Module.psm1'; the leading .\ breaks
    # the ISS module load Craft uses, so strip it (same fix as build-modules.ps1).
    $psd1Path = Join-Path $dst "$mod.psd1"
    $content  = Get-Content $psd1Path -Raw
    if ($content -match '\.\\\w+\.psm1') {
        ($content -replace '\.\\(\w+\.psm1)', '$1') | Set-Content $psd1Path -NoNewline -Force
    }

    Remove-Item $tmpOut -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host " OK" -ForegroundColor Green
}
} finally {
    Pop-Location
}

Write-Host "Done." -ForegroundColor Cyan
