<#
.SYNOPSIS
Sets the CIPP release version in every file that carries it.

.DESCRIPTION
The version lives in three files that must always agree:
  backend/version_latest.txt      (Assert-CippVersion reads this at runtime)
  frontend/package.json           ("version")
  frontend/public/version.json    ("version")

The script reads the current version from version_latest.txt, refuses to run if the three files
disagree, and rewrites all three with the new version. Either pass an explicit -Version or a
-Bump of major/minor/patch (patch by default). Files are edited with targeted text replacement so
their formatting is preserved. Nothing is committed or tagged; the release tag (vX.Y.Z) is still
created by hand and drives the container build.

.PARAMETER Version
Explicit semantic version to set, e.g. 11.0.1.

.PARAMETER Bump
Which component to increment from the current version: major, minor or patch. Default patch.

.EXAMPLE
./build/tools/Update-CippVersion.ps1
Bumps the patch version (11.0.0 -> 11.0.1).

.EXAMPLE
./build/tools/Update-CippVersion.ps1 -Bump minor

.EXAMPLE
./build/tools/Update-CippVersion.ps1 -Version 11.1.0 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump = 'patch'
)

$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Files = @{
    Txt         = Join-Path $Root 'backend\version_latest.txt'
    PackageJson = Join-Path $Root 'frontend\package.json'
    VersionJson = Join-Path $Root 'frontend\public\version.json'
}

$Current = (Get-Content -Path $Files.Txt -Raw).Trim()
if ($Current -notmatch '^\d+\.\d+\.\d+$') { throw "version_latest.txt holds '$Current', not a semantic version." }

# All three must already agree, otherwise a previous bump was incomplete and needs a look first.
$PkgVersion = (Get-Content -Path $Files.PackageJson -Raw | ConvertFrom-Json).version
$PubVersion = (Get-Content -Path $Files.VersionJson -Raw | ConvertFrom-Json).version
if ($PkgVersion -ne $Current -or $PubVersion -ne $Current) {
    throw "Version files disagree: version_latest.txt=$Current package.json=$PkgVersion version.json=$PubVersion"
}

if (-not $Version) {
    $Parts = [int[]]($Current -split '\.')
    switch ($Bump) {
        'major' { $Parts[0]++; $Parts[1] = 0; $Parts[2] = 0 }
        'minor' { $Parts[1]++; $Parts[2] = 0 }
        'patch' { $Parts[2]++ }
    }
    $Version = $Parts -join '.'
}
if ($Version -eq $Current) { Write-Host "Already at $Current, nothing to do."; return }

Write-Host "Updating CIPP version $Current -> $Version"

if ($PSCmdlet.ShouldProcess($Files.Txt, "write $Version")) {
    [System.IO.File]::WriteAllText($Files.Txt, "$Version`n")
}

# Only the top-level "version" key is touched. The first match is the package's own version;
# dependency ranges further down (e.g. "remark-parse": "^11.0.0") are left alone.
foreach ($Path in @($Files.PackageJson, $Files.VersionJson)) {
    $Text = Get-Content -Path $Path -Raw
    $Pattern = '(?m)^(\s*"version":\s*")' + [regex]::Escape($Current) + '(")'
    $Updated = [regex]::Replace($Text, $Pattern, ('${1}' + $Version + '${2}'), 1)
    if ($Updated -eq $Text) { throw "No top-level version key matching $Current found in $Path" }
    if ($PSCmdlet.ShouldProcess($Path, "write $Version")) {
        [System.IO.File]::WriteAllText($Path, $Updated)
    }
}

Write-Host "Done. Review with 'git diff', commit, then tag v$Version to trigger the release build."
