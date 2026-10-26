<#
.SYNOPSIS
    Splits intuneCollection.json into 256 bucket bundles for the frontend to fetch.

.DESCRIPTION
    A settings catalog policy references around 2% of the ~18k definitions in the catalog, so the
    UI fetches only the buckets it needs instead of downloading the whole 17MB file. This writes
    that layout into frontend\public\intune-definitions: 256 files named 00.json through ff.json,
    each a JSON object mapping definition hashes to definitions.

    Definitions are addressed by the SHA-256 of the setting definition id rather than by the id
    itself: ids run up to 278 characters, which would make unwieldy keys and once exceeded the
    260-character Windows MAX_PATH as filenames. Each definition is keyed by the first 16 hex
    characters of the hash, and the first 2 of those pick the bucket file it lives in.

    One file per definition would be cleaner still, but Azure Static Web Apps caps a deployment
    at 15,000 files and the catalog alone is ~18k definitions, so definitions sharing a hash
    prefix are bundled into one file. Each bundle is ~75KB raw and a few KB compressed.

    The frontend computes the same bucket and key with SubtleCrypto - see
    src\hooks\use-intune-collection.js. Both sides hash the UTF-8 bytes of the id and take the
    first 16 hex characters, so any change to the scheme has to be made in both places.

    It also writes _index\<platform>.json: a small per-platform search index the template
    authoring picker loads, since a hash-addressed bundle cannot answer "which settings exist".
    Settings that only ever appear beneath a parent carry parentId, because Intune
    rejects them on their own: the picker adds them through their top-level setting.

.PARAMETER CollectionPath
    Source catalog, with the construction fields Update-IntuneCollection.ps1 collects.

.PARAMETER OutputPath
    Destination folder. Defaults to frontend\public\intune-definitions.

.EXAMPLE
    .\Split-IntuneCollection.ps1

.NOTES
    Run after Update-IntuneCollection.ps1, which calls this automatically.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CollectionPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\frontend\public\intune-definitions')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CollectionPath)) {
    throw "Collection not found: $CollectionPath"
}

$CollectionPath = (Resolve-Path $CollectionPath).Path
Write-Host "Reading $CollectionPath..." -ForegroundColor Yellow

# JsonDocument rather than ConvertFrom-Json: GetRawText hands back each definition's original JSON,
# so nothing is reserialised and the output matches the source byte for byte.
$Document = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($CollectionPath))

# Rebuilt from scratch so definitions Intune has retired do not linger in stale bundles.
if (Test-Path $OutputPath) {
    Write-Host 'Removing previous output...' -ForegroundColor Yellow
    Remove-Item -Path $OutputPath -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $OutputPath -Force
$OutputPath = (Resolve-Path $OutputPath).Path

$Sha = [System.Security.Cryptography.SHA256]::Create()
$Bundles = [System.Collections.Generic.SortedDictionary[string, System.Text.StringBuilder]]::new()
$Hashes = @{}
$Written = 0
$Skipped = 0
$IndexByPlatform = @{}
$ParentOf = [System.Collections.Generic.Dictionary[string, string]]::new()

function Get-JsonString($Element, [string]$Name) {
    $Value = [System.Text.Json.JsonElement]::new()
    if ($Element.ValueKind -eq 'Object' -and $Element.TryGetProperty($Name, [ref]$Value) -and $Value.ValueKind -eq 'String') { $Value.GetString() }
}
function Get-JsonArray($Element, [string]$Name) {
    $Value = [System.Text.Json.JsonElement]::new()
    if ($Element.ValueKind -eq 'Object' -and $Element.TryGetProperty($Name, [ref]$Value) -and $Value.ValueKind -eq 'Array') { $Value.EnumerateArray() }
}

try {
    foreach ($Element in $Document.RootElement.EnumerateArray()) {
        # TryGetProperty takes a by-ref out parameter PowerShell cannot bind, so a missing 'id'
        # is caught rather than tested for.
        $Id = $null
        try { $Id = $Element.GetProperty('id').GetString() } catch { $Id = $null }

        if ([string]::IsNullOrWhiteSpace($Id)) {
            $Skipped++
            continue
        }

        $Hash = [System.Convert]::ToHexString(
            $Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Id))
        ).ToLowerInvariant().Substring(0, 16)

        # 64 bits over 18k ids makes a collision astronomically unlikely, but a silent one would
        # serve the wrong setting's name, so it is checked rather than assumed.
        if ($Hashes.ContainsKey($Hash)) {
            throw "Hash collision on '$Hash': '$Id' and '$($Hashes[$Hash])'. The naming scheme needs more bits."
        }
        $Hashes[$Hash] = $Id

        # Bundles are assembled as text - '{"<hash>":<raw>,...}' - rather than through a JSON
        # writer, so each definition's original bytes pass through untouched. Keys are hex, so
        # no escaping is needed.
        $Bucket = $Hash.Substring(0, 2)
        $Bundle = $null
        if ($Bundles.TryGetValue($Bucket, [ref]$Bundle)) {
            $null = $Bundle.Append(',')
        } else {
            $Bundle = [System.Text.StringBuilder]::new('{')
            $Bundles[$Bucket] = $Bundle
        }
        $null = $Bundle.Append('"').Append($Hash).Append('":').Append($Element.GetRawText())
        $Written++

        # Search index. Child relationships are only recorded on the parent (childIds, and each
        # option's dependedOnBy), so each child's parent is collected here for the index below.
        foreach ($Child in (Get-JsonArray $Element 'childIds')) { $null = $ParentOf.TryAdd($Child.GetString(), $Id) }
        foreach ($Option in (Get-JsonArray $Element 'options')) {
            foreach ($Dependent in (Get-JsonArray $Option 'dependedOnBy')) {
                $Referenced = Get-JsonString $Dependent 'dependedOnBy'
                if ($Referenced) { $null = $ParentOf.TryAdd($Referenced, $Id) }
            }
        }

        # visibility, not accessTypes: accessTypes reads 'none' for most configurable settings.
        $Visibility = Get-JsonString $Element 'visibility'
        if ($Visibility -and $Visibility -notmatch 'settingsCatalog') { continue }
        # Only the definition types frontend/src/utils/intune-setting-builder.js can build.
        if ((Get-JsonString $Element '@odata.type') -notmatch 'deviceManagementConfiguration(Choice|Simple)Setting(Collection)?Definition$|deviceManagementConfigurationSettingGroup(Collection)?Definition$') { continue }

        $Applicability = [System.Text.Json.JsonElement]::new()
        $null = $Element.TryGetProperty('applicability', [ref]$Applicability)
        $Description = Get-JsonString $Element 'description'
        if ($Description -and $Description.Length -gt 200) { $Description = $Description.Substring(0, 200).TrimEnd() + '...' }

        $Entry = [pscustomobject]@{
            id           = $Id
            displayName  = Get-JsonString $Element 'displayName'
            description  = $Description
            categoryName = Get-JsonString $Element 'categoryName'
            categoryId   = Get-JsonString $Element 'categoryId'
            technologies = Get-JsonString $Applicability 'technologies'
        }
        $Platform = Get-JsonString $Applicability 'platform'
        foreach ($P in ($Platform ? ($Platform -split ',').Trim() : @('unknown'))) {
            if (-not $IndexByPlatform.ContainsKey($P)) { $IndexByPlatform[$P] = [System.Collections.Generic.List[object]]::new() }
            $IndexByPlatform[$P].Add($Entry)
        }
    }

    foreach ($Entry in $Bundles.GetEnumerator()) {
        [System.IO.File]::WriteAllText(
            (Join-Path $OutputPath "$($Entry.Key).json"),
            $Entry.Value.Append('}').ToString(),
            [System.Text.UTF8Encoding]::new($false)
        )
    }
} finally {
    $Sha.Dispose()
    $Document.Dispose()
}

$IndexPath = Join-Path $OutputPath '_index'
$null = New-Item -ItemType Directory -Path $IndexPath -Force
foreach ($Platform in $IndexByPlatform.Keys) {
    $Indexed = [System.Collections.Generic.HashSet[string]]::new([string[]]$IndexByPlatform[$Platform].id)
    # A child is listed with its parent so the picker can add it through the top-level setting it
    # sits under; one whose chain leaves this platform's index cannot be added and is left out.
    $Rows = foreach ($Entry in $IndexByPlatform[$Platform]) {
        $Current = $Entry.id
        $Depth = 0
        while ($ParentOf.ContainsKey($Current) -and $Indexed.Contains($ParentOf[$Current]) -and $Depth -lt 8) {
            $Current = $ParentOf[$Current]
            $Depth++
        }
        if ($ParentOf.ContainsKey($Current)) { continue }
        if ($Depth -gt 0) { $Entry | Add-Member -Force -NotePropertyName parentId -NotePropertyValue $ParentOf[$Entry.id] }
        $Entry
    }
    $Rows = $Rows | Sort-Object displayName
    [System.IO.File]::WriteAllText(
        (Join-Path $IndexPath ('{0}.json' -f $Platform.ToLowerInvariant())),
        (ConvertTo-Json -InputObject @($Rows) -Depth 3 -Compress),
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host ('  index {0,-22} {1,6} settings' -f $Platform, @($Rows).Count)
}

Write-Host ''
Write-Host "Wrote $Written definitions across $($Bundles.Count) bundles to $OutputPath" -ForegroundColor Green
if ($Skipped -gt 0) {
    Write-Host "Skipped $Skipped entries with no id." -ForegroundColor Yellow
}
