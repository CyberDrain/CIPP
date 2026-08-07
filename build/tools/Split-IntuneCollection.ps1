<#
.SYNOPSIS
    Splits intuneCollection.json into one file per setting definition for the frontend to fetch.

.DESCRIPTION
    A settings catalog policy references around 2% of the ~18k definitions in the catalog, so the
    UI fetches the definitions it needs individually instead of downloading the whole 17MB file.
    This writes that per-definition layout into frontend\public\intune-definitions.

    Files are named by the SHA-256 of the setting definition id rather than by the id itself:
    ids run up to 278 characters, and frontend\public\intune-definitions\<id>.json exceeds the
    260-character Windows MAX_PATH, which would break checkout and build on Windows. The first
    byte of the hash is also used as a subdirectory so no single folder holds all 18k files.

    The frontend computes the same path with SubtleCrypto - see src\hooks\use-intune-collection.js.
    Both sides hash the UTF-8 bytes of the id and take the first 16 hex characters, so any change
    to the scheme has to be made in both places.

    The bundled backend\Config\intuneCollection.json is left alone: Compare-CIPPIntuneObject.ps1
    reads it directly and needs the whole catalog in one file.

.PARAMETER CollectionPath
    Source catalog. Defaults to backend\Config\intuneCollection.json.

.PARAMETER OutputPath
    Destination folder. Defaults to frontend\public\intune-definitions.

.EXAMPLE
    .\Split-IntuneCollection.ps1

.NOTES
    Run after Update-IntuneCollection.ps1, which calls this automatically.
#>

[CmdletBinding()]
param(
    [string]$CollectionPath = (Join-Path $PSScriptRoot '..\..\backend\Config\intuneCollection.json'),
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

# Rebuilt from scratch so definitions Intune has retired do not linger as stale files.
if (Test-Path $OutputPath) {
    Write-Host 'Removing previous output...' -ForegroundColor Yellow
    Remove-Item -Path $OutputPath -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $OutputPath -Force
$OutputPath = (Resolve-Path $OutputPath).Path

$Sha = [System.Security.Cryptography.SHA256]::Create()
$Buckets = [System.Collections.Generic.HashSet[string]]::new()
$Hashes = @{}
$Written = 0
$Skipped = 0
$IndexByPlatform = @{}
$ChildIds = [System.Collections.Generic.HashSet[string]]::new()

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

        $Bucket = $Hash.Substring(0, 2)
        if ($Buckets.Add($Bucket)) {
            $null = New-Item -ItemType Directory -Path (Join-Path $OutputPath $Bucket) -Force
        }

        [System.IO.File]::WriteAllText(
            (Join-Path $OutputPath "$Bucket\$Hash.json"),
            $Element.GetRawText(),
            [System.Text.UTF8Encoding]::new($false)
        )
        $Written++

        # --- search index -------------------------------------------------
        # The per-definition files above answer "what is this setting" for a policy that already
        # names one. They cannot answer "what settings are there", because a hash-addressed
        # directory cannot be listed - so adding a setting to a policy needs an index.
        #
        # It is deliberately small and separate from the definitions: enough to search and show a
        # result, and nothing else. Picking a result then fetches that one definition in full,
        # through the files above.
        $GetString = {
            param($Property)
            try { $Element.GetProperty($Property).GetString() } catch { $null }
        }

        # visibility, not accessTypes. accessTypes describes the access semantics of the underlying
        # CSP and reads 'none' for roughly three quarters of the catalog - including settings that
        # are plainly configurable - so filtering on it hides most of Intune. visibility is what
        # says whether the settings catalog surfaces a setting at all.
        $Visibility = & $GetString 'visibility'
        if ($Visibility -and $Visibility -notmatch 'settingsCatalog') { continue }

        $Applicability = $null
        try { $Applicability = $Element.GetProperty('applicability') } catch { $Applicability = $null }
        $Platform = if ($Applicability) { try { $Applicability.GetProperty('platform').GetString() } catch { $null } } else { $null }
        $Technologies = if ($Applicability) { try { $Applicability.GetProperty('technologies').GetString() } catch { $null } } else { $null }

        # Truncated rather than whole: a setting's description runs to several paragraphs and the
        # picker shows a single line of it, so carrying the rest would multiply the index for text
        # nobody sees. Enough to tell two similarly-named settings apart, and to search against.
        $Description = & $GetString 'description'
        if ($Description -and $Description.Length -gt 200) {
            $Description = $Description.Substring(0, 200).TrimEnd() + '…'
        }

        # Every setting this one pulls in: the children of a group, and the settings an option
        # reveals when it is chosen. Collected so the settings that are only ever children can be
        # kept out of the index below - a child added on its own is rejected by Intune with
        # "Setting contains parent setting that are not present in the policy", because the
        # relationship is only recorded on the parent and nothing on the child says it has one.
        foreach ($Property in @('childIds', 'dependedOnBy')) {
            try {
                $Node = $Element.GetProperty($Property)
                foreach ($Item in $Node.EnumerateArray()) {
                    $Referenced = if ($Item.ValueKind -eq 'String') { $Item.GetString() }
                    else { try { $Item.GetProperty('dependedOnBy').GetString() } catch { $null } }
                    if ($Referenced) { $null = $ChildIds.Add($Referenced) }
                }
            } catch { }
        }
        try {
            foreach ($Option in $Element.GetProperty('options').EnumerateArray()) {
                try {
                    foreach ($Item in $Option.GetProperty('dependedOnBy').EnumerateArray()) {
                        $Referenced = try { $Item.GetProperty('dependedOnBy').GetString() } catch { $null }
                        if ($Referenced) { $null = $ChildIds.Add($Referenced) }
                    }
                } catch { }
            }
        } catch { }

        $Entry = [ordered]@{
            id           = $Id
            displayName  = & $GetString 'displayName'
            description  = $Description
            categoryName = & $GetString 'categoryName'
            settingType  = & $GetString '@odata.type'
            technologies = $Technologies
            settingUsage = & $GetString 'settingUsage'
        }

        # A setting can apply to more than one platform, and is indexed under each so a macOS policy
        # and a Windows policy both find it without either loading the other's settings.
        $Platforms = if ([string]::IsNullOrWhiteSpace($Platform)) { @('unknown') } else { $Platform -split ',' | ForEach-Object { $_.Trim() } }
        foreach ($P in $Platforms) {
            if (-not $IndexByPlatform.ContainsKey($P)) {
                $IndexByPlatform[$P] = [System.Collections.Generic.List[object]]::new()
            }
            $IndexByPlatform[$P].Add([pscustomobject]$Entry)
        }
    }
} finally {
    $Sha.Dispose()
    $Document.Dispose()
}

# ---------------------------------------------------------------------------
# Write one index per platform.
# ---------------------------------------------------------------------------
$IndexPath = Join-Path $OutputPath '_index'
$null = New-Item -ItemType Directory -Path $IndexPath -Force

$Manifest = [System.Collections.Generic.List[object]]::new()
$Excluded = 0
foreach ($Platform in ($IndexByPlatform.Keys | Sort-Object)) {
    # Settings that only ever appear underneath another setting are dropped here rather than at
    # search time, because the index is the only place that knows: nothing on the child itself
    # records that it has a parent. They still reach a policy - as children of the parent that
    # names them - just never on their own.
    $Rows = $IndexByPlatform[$Platform] | Where-Object { -not $ChildIds.Contains($_.id) } | Sort-Object displayName
    $Excluded += (@($IndexByPlatform[$Platform]).Count - @($Rows).Count)
    # Lower-cased so a platform never becomes two files on a case-sensitive filesystem, and so the
    # client can derive the filename from a policy's platforms value without guessing at casing.
    $FileName = '{0}.json' -f $Platform.ToLowerInvariant()
    $Target = Join-Path $IndexPath $FileName
    [System.IO.File]::WriteAllText(
        $Target,
        ($Rows | ConvertTo-Json -Depth 5 -Compress),
        [System.Text.UTF8Encoding]::new($false)
    )
    $Manifest.Add([pscustomobject]@{
            platform = $Platform
            file     = $FileName
            count    = @($Rows).Count
            bytes    = (Get-Item $Target).Length
        })
}

[System.IO.File]::WriteAllText(
    (Join-Path $IndexPath 'manifest.json'),
    ($Manifest | ConvertTo-Json -Depth 5 -Compress),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ''
Write-Host "Search index (excluded $Excluded child-only settings):" -ForegroundColor Green
$Manifest | Sort-Object count -Descending | ForEach-Object {
    Write-Host ("  {0,-22} {1,6} settings  {2,8:N0} KB" -f $_.platform, $_.count, ($_.bytes / 1KB))
}

Write-Host ''
Write-Host "Wrote $Written definitions across $($Buckets.Count) folders to $OutputPath" -ForegroundColor Green
if ($Skipped -gt 0) {
    Write-Host "Skipped $Skipped entries with no id." -ForegroundColor Yellow
}
