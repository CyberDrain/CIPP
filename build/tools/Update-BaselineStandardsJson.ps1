<#
.SYNOPSIS
    Combines the baseline standard definitions into backend/Config/baselineStandards.json.
.DESCRIPTION
    Each baseline lives in its own file under backend/Config/BaselineStandards. standards.cipp.app
    reads one flat array in the frontend/src/data/standards.json shape, so this projects every
    enabled definition into that shape (variables become addedComponent fields named
    standards.<Name>.<variable>) and writes them as one file, sorted by name.

    The output is deterministic: the same definitions always produce the same bytes (LF, UTF-8, no
    BOM), so -Check can compare it byte for byte. Never edit the output by hand.
.EXAMPLE
    pwsh build/tools/Update-BaselineStandardsJson.ps1
.EXAMPLE
    pwsh build/tools/Update-BaselineStandardsJson.ps1 -Check
#>
[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '../../backend/Config/BaselineStandards'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '../../backend/Config/baselineStandards.json'),

    # Throw if the committed file differs from what would be generated, instead of writing it.
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$DisplayFields = @(
    'cat', 'tag', 'helpText', 'docsDescription', 'executiveText', 'label', 'impact', 'impactColour',
    'addedDate', 'powershellEquivalent', 'recommendedBy', 'requiredCapabilities', 'multiple'
)

$Definitions = [System.Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($File in Get-ChildItem -LiteralPath $SourcePath -Recurse -File -Filter '*.json') {
    $Definition = Get-Content -LiteralPath $File.FullName -Raw | ConvertFrom-Json
    if (-not $Definition.name) { throw "$($File.FullName) has no name." }
    if ($Definitions.ContainsKey($Definition.name)) { throw "Duplicate baseline name '$($Definition.name)' in $($File.FullName)." }
    if ($Definition.disabled -ne $true) { $Definitions.Add($Definition.name, $Definition) }
}

if ($Definitions.Count -lt 100) {
    throw "Only $($Definitions.Count) baseline definitions found under $SourcePath - refusing to write."
}

$Items = [System.Collections.Generic.List[object]]::new()
# The site skips entries without name/label/helpText/impact, so this note is never rendered.
$Items.Add([ordered]@{
        '$comment' = 'GENERATED FILE - DO NOT EDIT BY HAND. Built from backend/Config/BaselineStandards by build/tools/Update-BaselineStandardsJson.ps1; edit the definitions and rerun the script.'
    })

foreach ($Definition in $Definitions.Values) {
    $Item = [ordered]@{ name = "standards.$($Definition.name)" }
    foreach ($Field in $DisplayFields) {
        if ($null -ne $Definition.$Field) { $Item[$Field] = $Definition.$Field }
    }
    $Item.addedComponent = @(
        foreach ($Variable in @($Definition.variables.PSObject.Properties)) {
            $Component = [ordered]@{ name = "standards.$($Definition.name).$($Variable.Name)" }
            foreach ($Property in $Variable.Value.PSObject.Properties) { $Component[$Property.Name] = $Property.Value }
            $Component
        }
    )
    $Items.Add($Item)
}

$Json = (ConvertTo-Json -InputObject $Items -Depth 100) -replace "`r`n", "`n"
$Json = "$Json`n"
$Resolved = [System.IO.Path]::GetFullPath($OutputPath)

if ($Check) {
    $Current = if (Test-Path -LiteralPath $Resolved) { [System.IO.File]::ReadAllText($Resolved) -replace "`r`n", "`n" } else { '' }
    if ($Current -cne $Json) {
        throw "$Resolved is out of date with backend/Config/BaselineStandards. Regenerate with: pwsh build/tools/Update-BaselineStandardsJson.ps1"
    }
    Write-Host "$Resolved is up to date ($($Definitions.Count) baselines)."
    return
}

[System.IO.File]::WriteAllText($Resolved, $Json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $($Definitions.Count) baselines to $Resolved."
