# Build CIPP PowerShell modules for Docker or local dev.
#
# Compiles PS modules via ModuleBuilder, copies pre-built/binary modules,
# and stages Config, Shared, and version files into the target backend dir.
#
# Override source paths via parameters, env vars, or edit defaults below.
param(
    [string]$SourceModules = ($env:CRAFT_SOURCE_MODULES ?? 'C:\Github\CIPP-API\Modules'),
    [string]$TargetModules = "$PSScriptRoot\..\..\backend\Modules",
    [string]$OutputDir     = "$PSScriptRoot\..\..\backend\Output",
    [string[]]$Modules     = @('CIPPCore','CIPPHTTP','CIPPStandards','CIPPDB','CIPPAlerts','CIPPBaselines','CIPPActivityTriggers','CippExtensions','CIPPPwPush')
)

# ─────────────────────────────────────────────────────────────
# Module Build
# ─────────────────────────────────────────────────────────────
$sourceModulesPath = (Resolve-Path $SourceModules).Path
$targetModulesPath = [System.IO.Path]::GetFullPath($TargetModules)
$outputDirPath     = [System.IO.Path]::GetFullPath($OutputDir)

Import-Module -Name Metadata -RequiredVersion 1.5.7 -Force
Import-Module -Name Configuration -RequiredVersion 1.6.0 -Force
Import-Module -Name ModuleBuilder -RequiredVersion 3.1.8 -Force

Write-Host "`n=== Building PS Modules ===" -ForegroundColor Cyan
Write-Host "  Source: $sourceModulesPath"

Set-Location $sourceModulesPath
foreach ($mod in $Modules) {
    Write-Host "  Building $mod ..." -NoNewline
    try {
        $result = Build-Module -SourcePath (Join-Path $mod 'build.psd1') -OutputDirectory $outputDirPath -ErrorAction Stop
        Write-Host " OK ($($result.ModuleBase))" -ForegroundColor Green
    } catch {
        throw " FAILED: $_"
    }
}

Write-Host "`n=== Deploying Modules ===" -ForegroundColor Green
foreach ($mod in $Modules) {
    $src = Join-Path $outputDirPath $mod
    $dst = Join-Path $targetModulesPath $mod
    if (-not (Test-Path $src)) { Write-Host "  SKIP $mod" -ForegroundColor Yellow; continue }

    # Copy full build output (includes .psm1, .psd1, and any CopyPaths like data/)
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $src $dst -Recurse -Force

    # Fix RootModule relative path (ModuleBuilder outputs '.\Module.psm1' which ISS can't load)
    $psd1Path = Join-Path $dst "$mod.psd1"
    $content = Get-Content $psd1Path -Raw
    if ($content -match '\.\\\w+\.psm1') {
        $content = $content -replace '\.\\(\w+\.psm1)', '$1'
        Set-Content $psd1Path $content -NoNewline -Force
    }

    $items = Get-ChildItem $dst -Recurse -File
    $lines = (Get-Content (Join-Path $dst "$mod.psm1")).Count
    Write-Host "  $mod : $lines lines, $($items.Count) files"
}

Remove-Item $outputDirPath -Recurse -Force -ErrorAction SilentlyContinue

# Remove build-time source artifacts from the target (not part of ModuleBuilder output)
Write-Host "`n=== Cleaning source artifacts ===" -ForegroundColor Green
foreach ($mod in $Modules) {
    $dst = Join-Path $targetModulesPath $mod
    if (-not (Test-Path $dst)) { continue }
    $cleaned = @()
    foreach ($sub in @('Public', 'Private', 'Classes', 'Enum', 'build.psd1')) {
        $path = Join-Path $dst $sub
        if (Test-Path $path) { Remove-Item $path -Recurse -Force; $cleaned += $sub }
    }
    if ($cleaned) { Write-Host "  $mod : removed $($cleaned -join ', ')" }
}

# Copy pre-built/binary modules that aren't compiled by ModuleBuilder
Write-Host "`n=== Copying pre-built modules ===" -ForegroundColor Green
foreach ($dir in (Get-ChildItem $sourceModulesPath -Directory)) {
    if ($Modules -contains $dir.Name) { continue }
    $dst = Join-Path $targetModulesPath $dir.Name
    if (-not (Test-Path $dst)) {
        Copy-Item $dir.FullName $dst -Recurse -Force
        Write-Host "  $($dir.Name) : copied"
    }
}

# Copy supporting dirs (Config, Shared, etc.) from API source root
$sourceRoot = Split-Path $sourceModulesPath
$targetRoot = [System.IO.Path]::GetFullPath((Join-Path $targetModulesPath '..'))

Write-Host "`n=== Copying Config ===" -ForegroundColor Green
$sourceConfig = Join-Path $sourceRoot 'Config'
$targetConfig = Join-Path $targetRoot 'Config'
if (Test-Path $sourceConfig) {
    New-Item -ItemType Directory -Path $targetConfig -Force | Out-Null
    Copy-Item "$sourceConfig\*" $targetConfig -Recurse -Force
    $configCount = (Get-ChildItem $targetConfig -Recurse -File).Count
    Write-Host "  Config : $configCount files"
} else {
    Write-Host "  SKIP Config (not found at $sourceConfig)" -ForegroundColor Yellow
}

Write-Host "`n=== Copying CIPPSharp DLL ===" -ForegroundColor Green
$sourceCIPPSharp = Join-Path $sourceRoot 'Shared' 'CIPPSharp'
$targetCIPPSharpBin = [System.IO.Path]::GetFullPath((Join-Path $targetRoot 'Shared' 'CIPPSharp' 'bin'))
if (Test-Path $sourceCIPPSharp) {
    New-Item -ItemType Directory -Path $targetCIPPSharpBin -Force | Out-Null
    Copy-Item (Join-Path $sourceCIPPSharp 'bin' 'CIPPSharp.dll') (Join-Path $targetCIPPSharpBin 'CIPPSharp.dll') -Force
    Write-Host "  CIPPSharp.dll : copied"
} else {
    Write-Host "  SKIP CIPPSharp (not found at $sourceCIPPSharp)" -ForegroundColor Yellow
}

Write-Host "`nDone" -ForegroundColor Cyan
