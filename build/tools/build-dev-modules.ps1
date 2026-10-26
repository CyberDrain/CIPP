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
    [string[]] $Modules       = @('CIPPCore','CIPPHTTP','CIPPStandards','CIPPDB','CIPPAlerts','CIPPBaselines','CIPPActivityTriggers','CippExtensions','CIPPPwPush', 'CIPPTests'),
    # Skip the openapi.json regeneration (the slowest step). The watcher passes this so a
    # CIPPHTTP edit's container restart is not blocked on the spec, then regenerates it in
    # the background itself. The initial build leaves it off so the spec is present at startup.
    [switch]   $SkipOpenApi
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
        Build-Module -SourcePath $buildManifest -OutputDirectory $tmpOut -ErrorAction Stop | Out-Null

        if ($mod -eq 'CIPPTests') {
            # cipp-api enumerates the test source at runtime to discover tests, so for this
            # module the source tree ships alongside the compiled module instead of being
            # replaced by it.
            #
            # Copy the *contents*, not the directory: Copy-Item of a directory onto a
            # destination that already exists puts it inside, giving
            # .devmodules/CIPPTests/CIPPTests. The watcher recompiles on every save, so the
            # directory form nests one level deeper each time a test file is touched.
            $srcTree = Join-Path $sourceModulesPath $mod
            $dstTree = Join-Path $outputModulesPath $mod
            New-Item -ItemType Directory -Path $dstTree -Force | Out-Null
            # heal nesting left behind by earlier runs. only the nested copy is removed --
            # $dstTree itself is bind-mounted into the running container, and deleting a
            # mount root out from under Docker breaks the mount
            $stale = Join-Path $dstTree $mod
            if (Test-Path $stale) { Remove-Item $stale -Recurse -Force }
            # Mirror the source: a test file deleted or moved in the source must disappear here too,
            # or cipp-api keeps listing a test whose function no longer exists.
            $publicDst = Join-Path $dstTree 'Public'
            if (Test-Path $publicDst) { Remove-Item $publicDst -Recurse -Force }
            Copy-Item (Join-Path $srcTree '*') $dstTree -Recurse -Force
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

# help cache for ListFunctionParameters, AST-extracted from CIPPCore source,
# cheap enough to regenerate on every CIPPCore build (watcher passes -Modules
# per save, skip when CIPPCore didn't change). the one write into the source
# tree this script does; the file is gitignored so the working tree stays clean
if ($Modules -contains 'CIPPCore') {
    $paramCachePath = Join-Path (Split-Path -Parent $sourceModulesPath) 'Config' 'function-parameters.json'
    try {
        & (Join-Path $PSScriptRoot 'build-function-parameters.ps1') `
            -ModulePath (Join-Path $sourceModulesPath 'CIPPCore') -OutputPath $paramCachePath
    } catch {
        Write-Host "function-parameters.json generation FAILED ($_); missing cache is slow, stale cache hides new functions from the scheduler" -ForegroundColor Red
    }
}

# openapi.json, AST-extracted from the CIPPHTTP entrypoints. Regenerated on every
# CIPPHTTP build so the local MCP tool list matches the endpoints you just edited.
# unlike function-parameters.json this file IS committed, so a change here shows up
# as a working-tree diff — that diff is the point, it belongs in the same commit as
# the endpoint change
if ($Modules -contains 'CIPPHTTP' -and -not $SkipOpenApi) {
    $backendPath = Split-Path -Parent $sourceModulesPath
    try {
        & (Join-Path $PSScriptRoot 'build-openapi.ps1') `
            -EntrypointPath (Join-Path $sourceModulesPath 'CIPPHTTP' 'Public' 'Entrypoints' 'HTTP Functions') `
            -ModulesPath $sourceModulesPath `
            -FrontendPath (Join-Path (Split-Path -Parent $backendPath) 'frontend' 'src') `
            -OverridePath (Join-Path $backendPath 'Config' 'openapi-overrides') `
            -OutputPath (Join-Path $backendPath 'Config' 'openapi.json')
    } catch {
        Write-Host "openapi.json generation FAILED ($_); a stale spec means the MCP tool list no longer matches the API" -ForegroundColor Red
    }
}

Write-Host "Done." -ForegroundColor Cyan
