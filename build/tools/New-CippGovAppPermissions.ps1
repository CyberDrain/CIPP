<#
.SYNOPSIS
Builds the Azure Government app's Microsoft Graph permissions from CIPP-SAM's manifest.

.DESCRIPTION
A GCC High or DoD direct tenant signs in with a separate app registered in Azure Government
(docs/setup/installation/government-direct-tenants.md). That app needs the same Microsoft Graph
permissions as CIPP-SAM, delegated and application, but the commercial manifest
(backend/Config/SAMManifest.json) cannot be pasted into it: Microsoft Graph in Azure Government uses
different ids for some permissions and does not have others.

This script translates each permission in the manifest's Microsoft Graph entry to its name
(backend/Config/PermissionsTranslator.json) and looks that name up, with the same type (delegated =
Scope, application = Role), in the Azure Government Microsoft Graph service principal you exported.
It returns the requiredResourceAccess entry for the government app and warns about every permission
that does not exist there. Nothing is sent anywhere; it only reads the three files.

Export the service principal from Azure Government first, for example with the Azure CLI:

    az cloud set --name AzureUSGovernment
    az login
    az rest --uri "https://graph.microsoft.us/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?`$select=appId,appRoles,oauth2PermissionScopes" > govgraph.json

(DoD: use https://dod-graph.microsoft.us.) Graph Explorer or Microsoft Graph PowerShell signed in to the
government tenant work too; the file needs the appRoles and oauth2PermissionScopes arrays.

.PARAMETER ServicePrincipalPath
The exported Azure Government Microsoft Graph service principal (JSON with appRoles and
oauth2PermissionScopes, each item with id and value).

.PARAMETER OutFile
Optional. Writes the requiredResourceAccess entry as JSON to this file.

.PARAMETER ManifestPath
CIPP-SAM's manifest. Defaults to backend/Config/SAMManifest.json in this repository.

.PARAMETER TranslatorPath
Permission id to name lookup. Defaults to backend/Config/PermissionsTranslator.json.

.OUTPUTS
An object with resourceAppId and resourceAccess (the entry to put in the government app's
requiredResourceAccess) and Missing (the manifest permissions Azure Government does not have).

.EXAMPLE
./build/tools/New-CippGovAppPermissions.ps1 -ServicePrincipalPath ./govgraph.json -OutFile ./gov-graph-permissions.json

In the government app's Manifest, replace the requiredResourceAccess item whose resourceAppId is
00000003-0000-0000-c000-000000000000 with the content of gov-graph-permissions.json, save, then grant
admin consent.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServicePrincipalPath,

    [string]$OutFile,

    [string]$ManifestPath,

    [string]$TranslatorPath
)

$ErrorActionPreference = 'Stop'

# This script lives in build/tools/, so the repo root is two levels up.
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $ManifestPath) { $ManifestPath = Join-Path $RepoRoot 'backend/Config/SAMManifest.json' }
if (-not $TranslatorPath) { $TranslatorPath = Join-Path $RepoRoot 'backend/Config/PermissionsTranslator.json' }

$GraphAppId = '00000003-0000-0000-c000-000000000000'

$Manifest = [System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
$Translator = [System.IO.File]::ReadAllText($TranslatorPath) | ConvertFrom-Json
$ServicePrincipal = [System.IO.File]::ReadAllText($ServicePrincipalPath) | ConvertFrom-Json

if (-not $ServicePrincipal.appRoles -or -not $ServicePrincipal.oauth2PermissionScopes) {
    throw "$ServicePrincipalPath does not contain appRoles and oauth2PermissionScopes. Export the Microsoft Graph service principal with `$select=appId,appRoles,oauth2PermissionScopes."
}
if ($ServicePrincipal.appId -and $ServicePrincipal.appId -ne $GraphAppId) {
    throw "$ServicePrincipalPath is the service principal of $($ServicePrincipal.appId), not Microsoft Graph ($GraphAppId)."
}

# Commercial permission id -> name.
$NameById = @{}
foreach ($Entry in $Translator) {
    if ($Entry.id -and $Entry.value -and -not $NameById.ContainsKey($Entry.id)) { $NameById[$Entry.id] = $Entry.value }
}

# Azure Government name -> id, per type. Names are case-sensitive in Graph, so match exactly.
$GovIds = @{
    Scope = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    Role  = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
}
foreach ($Scope in $ServicePrincipal.oauth2PermissionScopes) { if ($Scope.value) { $GovIds.Scope[$Scope.value] = $Scope.id } }
foreach ($Role in $ServicePrincipal.appRoles) { if ($Role.value) { $GovIds.Role[$Role.value] = $Role.id } }

$GraphEntry = $Manifest.requiredResourceAccess | Where-Object { $_.resourceAppId -eq $GraphAppId } | Select-Object -First 1
if (-not $GraphEntry) { throw "$ManifestPath has no Microsoft Graph entry." }

$Access = [System.Collections.Generic.List[object]]::new()
$Missing = [System.Collections.Generic.List[object]]::new()
$Seen = [System.Collections.Generic.HashSet[string]]::new()
foreach ($Permission in $GraphEntry.resourceAccess) {
    $Type = if ($Permission.type -eq 'Role') { 'Role' } else { 'Scope' }
    $Label = if ($Type -eq 'Role') { 'application' } else { 'delegated' }
    $Name = $NameById[$Permission.id]
    if (-not $Name) {
        $Missing.Add([pscustomobject]@{ Name = $Permission.id; Type = $Label; Reason = 'not in PermissionsTranslator.json' })
        continue
    }
    $GovId = $null
    if (-not $GovIds[$Type].TryGetValue($Name, [ref]$GovId)) {
        $Missing.Add([pscustomobject]@{ Name = $Name; Type = $Label; Reason = 'not in Azure Government Microsoft Graph' })
        continue
    }
    if ($Seen.Add("$Type|$GovId")) {
        $Access.Add([ordered]@{ id = $GovId; type = $Type })
    }
}

foreach ($Item in $Missing) {
    Write-Warning "Skipped $($Item.Type) permission $($Item.Name): $($Item.Reason)."
}

$Result = [ordered]@{ resourceAppId = $GraphAppId; resourceAccess = @($Access) }
if ($OutFile) {
    $Json = ConvertTo-Json -InputObject $Result -Depth 5
    [System.IO.File]::WriteAllText($OutFile, ($Json -replace "`r`n", "`n") + "`n")
}

[pscustomobject]@{
    resourceAppId  = $GraphAppId
    resourceAccess = @($Access)
    Missing        = @($Missing)
}
