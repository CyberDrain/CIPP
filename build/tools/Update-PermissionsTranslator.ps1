<#
.SYNOPSIS
Updates backend/Config/PermissionsTranslator.json from AzAdvertizer's published Entra ID API
permissions dataset.

.DESCRIPTION
PermissionsTranslator.json is a GUID -> scope-value lookup used by Add-CIPPDelegatedPermission.ps1:
the oauth2PermissionGrants API is granted string scope values (e.g. "Exchange.ManageV2"), not GUIDs,
so every required permission GUID is translated to its value through this file. A GUID that is missing
from the file is silently dropped from the grant - the permission never applies even though a manual
consent in the tenant resolves it fine.

The authoritative source spans many first-party resource apps (Microsoft Graph, Office 365 Exchange
Online, Partner Center, Defender, SharePoint, Teams, ...), which is why a Graph-only feed is not
enough. AzAdvertizer (https://www.azadvertizer.net, by Julian Hayward) publishes the full set as an
unauthenticated JSON file, so - like the license SKU data - this can be refreshed with no credentials.

Current-file GUIDs that are absent from the source (e.g. Partner Center user_impersonation) are
preserved, so a refresh only ever adds coverage; it never regresses an existing translation.

.EXAMPLE
Update-PermissionsTranslator.ps1

Downloads the latest permissions dataset and rewrites backend/Config/PermissionsTranslator.json.

.NOTES
Runs in CI via .github/workflows/update-permissions-translator.yml, which opens a PR when the file
changes. Keep this script cross-platform - CI runs it on Linux, and the file is written with LF
regardless of host so a Windows local run and the Linux CI run produce identical bytes.
#>

$ErrorActionPreference = 'Stop'

# This script lives in build/tools/, so the repo root is two levels up.
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TranslatorPath = Join-Path $RepoRoot 'backend/Config/PermissionsTranslator.json'
# The frontend translates permission GUIDs to names from this byte-identical copy.
$FrontendTranslatorPath = Join-Path $RepoRoot 'frontend/public/permissionsTranslator.json'

# AzAdvertizer serves this gzipped; Invoke-RestMethod negotiates and decompresses automatically.
$SourceUrl = 'https://www.azadvertizer.net/azEntraIdAPIpermissionsAdvertizer.json'
Write-Host "Downloading Entra API permissions from $SourceUrl ..." -ForegroundColor Yellow
$Source = Invoke-RestMethod -Uri $SourceUrl -Method Get

# That endpoint could serve an error page or a truncated file. Never rewrite the translator on top of
# one: assert a sane row count and a couple of well-known GUIDs before trusting the payload.
if (@($Source).Count -lt 2000) {
    throw "Permissions source returned only $(@($Source).Count) entries - refusing to continue."
}
$SourceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($Id in $Source.p_id) { if ($Id) { [void]$SourceIds.Add($Id) } }
foreach ($Anchor in @(
        @{ Id = 'df021288-bdef-4463-88db-98f22de89214'; Name = 'Graph User.Read.All (application)' }
        @{ Id = '44d6b5f2-d42b-4fa7-b999-1c5fcab98e4d'; Name = 'Exchange.ManageV2 (delegated)' }
    )) {
    if (-not $SourceIds.Contains($Anchor.Id)) {
        throw "Permissions source is missing the well-known GUID for $($Anchor.Name) ($($Anchor.Id)) - looks truncated or reshaped."
    }
}
Write-Host "Downloaded $(@($Source).Count) permission entries." -ForegroundColor Green

# Reshape to the translator's flat shape. Application permissions (p_type 'ar') carry ar_dn/ar_dc;
# delegated permissions (p_type 'oa') carry the admin-consent oa_aCsDn/oa_aCsDc. Only id + value are
# read at runtime; displayName/description/origin are informational, so the resource name is folded
# into origin for easier debugging of "why didn't this scope apply".
$Translated = foreach ($Perm in $Source) {
    if (-not $Perm.p_id -or -not $Perm.p) { continue }
    $IsAppRole = $Perm.p_type -eq 'ar'
    $Type = if ($IsAppRole) { 'Application' } else { 'Delegated' }
    $Origin = if ($Perm.dn) { '{0} ({1})' -f $Type, $Perm.dn } else { $Type }
    [ordered]@{
        description = if ($IsAppRole) { $Perm.ar_dc } else { $Perm.oa_aCsDc }
        displayName = if ($IsAppRole) { $Perm.ar_dn } else { $Perm.oa_aCsDn }
        id          = $Perm.p_id
        origin      = $Origin
        value       = $Perm.p
    }
}

# Preserve any current GUIDs the source does not carry, normalising both historical shapes (lowercase
# 'origin' vs capital 'Origin' + userConsent* fields) so the output is uniform.
$Existing = Get-Content -Path $TranslatorPath -Raw | ConvertFrom-Json
$Preserved = foreach ($Old in $Existing) {
    if (-not $Old.id -or $SourceIds.Contains($Old.id)) { continue }
    [ordered]@{
        description = $Old.description ?? $Old.userConsentDescription
        displayName = $Old.displayName ?? $Old.userConsentDisplayName
        id          = $Old.id
        origin      = $Old.origin ?? $Old.Origin
        value       = $Old.value
    }
}
$PreservedCount = @($Preserved).Count
if ($PreservedCount -gt 0) {
    Write-Host "Preserving $PreservedCount GUID(s) not present in the source." -ForegroundColor Yellow
}

# Deterministic order (value then id, since value is not unique) keeps refresh diffs to real changes.
$Sorted = @(
    $Translated
    $Preserved
) | Sort-Object -Property value, id

# One row per GUID: this is a lookup table and the runtime resolves id -> value with no resource
# context, so a duplicated id would return an array. A handful of legacy GUIDs are defined by two
# resource apps with different values (e.g. ef54d2bf-... is both Graph's Calendars.ReadWrite and
# EXO's Calendars.ReadWrite.All) - inherently ambiguous without resource context; the sort above
# just makes "keep first" deterministic.
$Seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$All = foreach ($Entry in $Sorted) {
    if ($Seen.Add($Entry.id)) { $Entry }
}

# Write LF explicitly (no BOM, single trailing newline) so host platform cannot affect the bytes.
$Json = (@($All) | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($TranslatorPath, $Json + "`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($FrontendTranslatorPath, $Json + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $(@($All).Count) entries to $TranslatorPath and $FrontendTranslatorPath." -ForegroundColor Green
