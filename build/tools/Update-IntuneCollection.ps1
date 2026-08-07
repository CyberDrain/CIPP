<#
.SYNOPSIS
    Regenerates the Intune setting catalog lookup files from the Microsoft Graph API.

.DESCRIPTION
    Queries the Microsoft Graph beta endpoints for all Intune device management
    configuration setting definitions and their categories, then writes:

      backend\Config\intuneCollection.json     the whole catalog, read by
                                               Compare-CIPPIntuneObject.ps1 at runtime
      backend\Config\intuneCategories.json     the category records, whole
      frontend\public\intune-definitions\      one file per setting definition, which is
                                               what the UI fetches (see
                                               Split-IntuneCollection.ps1 for why)
      frontend\public\intuneCategories.json    the category records, whole
      frontend\public\intuneCollection.json    the whole catalog again, kept in step

    Each definition carries both what it is called and what it takes to build one: the
    definition's own @odata.type, its valueDefinition, defaultOptionId, applicability and
    dependency links. Naming a setting needs none of that; creating one from nothing needs
    all of it.

    The definitions translate raw settingDefinitionIds into human-readable display
    names. Each carries categoryName for grouping, plus categoryId to join against
    the category records - display names are reused across products, so the id is
    the only thing that separates, say, Google Chrome's "Content settings" from
    Microsoft Edge's, or nests them the way the Intune console does.

    Requires Initialize-DevEnvironment.ps1 to be dot-sourced (or it will be loaded
    automatically), and a valid CIPP-managed TenantId to obtain a Graph token.

.PARAMETER TenantId
    A tenant domain or GUID that CIPP manages. Used only to obtain a Graph
    authentication token — the configurationSettings endpoint returns Microsoft's
    global catalog, not tenant-specific data.

.EXAMPLE
    # From the tools folder, after initialising your dev environment:
    . .\Initialize-DevEnvironment.ps1
    .\Update-IntuneCollection.ps1 -TenantId contoso.onmicrosoft.com

.NOTES
    Permissions required: DeviceManagementConfiguration.Read.All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Ensure the CIPP module is loaded
# ---------------------------------------------------------------------------
if (-not (Get-Module -Name CIPPCore)) {
    Write-Host 'CIPPCore not loaded — running Initialize-DevEnvironment.ps1...' -ForegroundColor Yellow
    . (Join-Path $PSScriptRoot 'Initialize-DevEnvironment.ps1')
}

# ---------------------------------------------------------------------------
# Fetch all configurationSettings (New-GraphGetRequest auto-paginates)
# ---------------------------------------------------------------------------
Write-Host 'Fetching Intune configuration settings (this may take a while)...' -ForegroundColor Yellow

$allSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationSettings' -tenantid $TenantId -NoAuthCheck $true

Write-Host "Total settings fetched: $($allSettings.Count)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Fetch the category names, so the template editor can group settings the way the
# Intune console does. A setting carries only a categoryId; the display name for it
# lives on a separate collection.
# ---------------------------------------------------------------------------
Write-Host 'Fetching configuration categories...' -ForegroundColor Yellow

$categoryNames = @{}
$categories = @()
try {
    $allCategories = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationCategories' -tenantid $TenantId -NoAuthCheck $true
    foreach ($Category in $allCategories) {
        if ($Category.id -and $Category.displayName) {
            $categoryNames[$Category.id] = $Category.displayName
        }
    }

    # Kept whole, not just as a name lookup. Category display names are not unique - over 200 of them
    # are reused across products, so "Content settings" belongs to both Google Chrome and Microsoft
    # Edge - and the parent/root ids are the only thing that tells those apart or nests them the way
    # the Intune console does.
    $categories = $allCategories | Sort-Object -Property id | ForEach-Object {
        [PSCustomObject]@{
            id               = $_.id
            displayName      = $_.displayName
            description      = $_.PSObject.Properties['description']?.Value
            helpText         = $_.PSObject.Properties['helpText']?.Value
            parentCategoryId = $_.PSObject.Properties['parentCategoryId']?.Value
            rootCategoryId   = $_.PSObject.Properties['rootCategoryId']?.Value
            childCategoryIds = $_.PSObject.Properties['childCategoryIds']?.Value
            platforms        = $_.PSObject.Properties['platforms']?.Value
            technologies     = $_.PSObject.Properties['technologies']?.Value
        }
    }

    Write-Host "Total categories fetched: $($categoryNames.Count)" -ForegroundColor Green
} catch {
    # Not fatal: without categoryName the editor falls back to the namespace inside each setting id,
    # so a tenant that cannot read this collection still gets a grouped - if uglier - editor.
    Write-Host "Could not fetch categories, settings will have no categoryName: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Transform to the shape expected by CIPP
# Shape: [{ id, displayName, description, helpText, infoUrls, categoryName,
#           options: [{id, displayName, description, helpText}] | null }]
# ---------------------------------------------------------------------------
Write-Host 'Transforming data...' -ForegroundColor Yellow

$collection = $allSettings | Sort-Object -Property id | ForEach-Object {
    $rawOptions = $_.PSObject.Properties['options']?.Value
    $options = if ($rawOptions -and $rawOptions.Count -gt 0) {
        $rawOptions | ForEach-Object {
            [PSCustomObject]@{
                id           = $_.PSObject.Properties['itemId']?.Value
                displayName  = $_.PSObject.Properties['displayName']?.Value
                description  = $_.PSObject.Properties['description']?.Value
                helpText     = $_.PSObject.Properties['helpText']?.Value
                # The typed value behind the option, with its own @odata.type. Reading a policy only
                # ever needs the option's id; building one needs to know what value to write and what
                # to declare it as.
                optionValue  = $_.PSObject.Properties['optionValue']?.Value
                # Which other settings this option brings into play. Choosing a parent option in the
                # Intune console reveals its children, and a builder that ignores this produces a
                # policy with a choice selected and none of the settings that choice requires.
                dependentOn  = $_.PSObject.Properties['dependentOn']?.Value
                dependedOnBy = $_.PSObject.Properties['dependedOnBy']?.Value
            }
        }
    } else {
        $null
    }

    # The name is denormalised so the common case - showing a heading - needs nothing but the
    # setting. The id rides along because display names are not unique: anything that has to
    # disambiguate or nest categories joins on this against intuneCategories.json.
    $CategoryId = $_.PSObject.Properties['categoryId']?.Value
    $CategoryName = if ($CategoryId) { $categoryNames[$CategoryId] } else { $null }

    [PSCustomObject]@{
        id           = $_.id
        displayName  = $_.displayName
        description  = $_.description
        helpText     = $_.helpText
        infoUrls     = $_.infoUrls
        categoryId   = $CategoryId
        categoryName = $CategoryName
        options      = $options

        # Everything below exists so a setting can be *constructed*, not just named. Reading a
        # policy back only needs a display name, which is all this file used to carry; creating a
        # setting from nothing needs to know what kind of instance to emit, what value shape it
        # takes, and whether the setting even applies to the policy being built.
        #
        # deviceManagementConfiguration{Choice,Simple,SettingGroup,...}SettingDefinition - decides
        # which settingInstance @odata.type to write.
        '@odata.type'     = $_.PSObject.Properties['@odata.type']?.Value
        # For simple settings: the value type, and its format/min/max. Without it there is no way to
        # tell a string setting from an integer or a secret.
        valueDefinition   = $_.PSObject.Properties['valueDefinition']?.Value
        # The option a new choice setting should start on.
        defaultOptionId   = $_.PSObject.Properties['defaultOptionId']?.Value
        # platform, technologies and deviceMode live under here, not at the top level. A picker uses
        # them to avoid offering a macOS setting for a Windows policy.
        applicability     = $_.PSObject.Properties['applicability']?.Value
        # 'add,delete,get,replace' or similar. A setting without add/replace cannot be configured.
        accessTypes       = $_.PSObject.Properties['accessTypes']?.Value
        # 'configuration' vs 'compliance' - the two are not interchangeable between policy types.
        settingUsage      = $_.PSObject.Properties['settingUsage']?.Value
        # Whether Intune surfaces it in the settings catalog, in templates, or neither.
        visibility        = $_.PSObject.Properties['visibility']?.Value
        rootDefinitionId  = $_.PSObject.Properties['rootDefinitionId']?.Value
        # The settings a group contains, stated directly. dependedOnBy carries the same links the
        # long way round, but only childIds says "these belong to me".
        childIds          = $_.PSObject.Properties['childIds']?.Value
        # How many entries a collection may hold. Intune enforces these and rejects the whole policy
        # when they are exceeded - the ASR rules group allows exactly one - so an editor that offers
        # to add a row without them produces a template that validates locally and fails on deploy.
        minimumCount      = $_.PSObject.Properties['minimumCount']?.Value
        maximumCount      = $_.PSObject.Properties['maximumCount']?.Value
        # Synonyms Intune's own search matches on, so a picker can find a setting by the name people
        # actually use for it rather than only by its display name.
        keywords          = $_.PSObject.Properties['keywords']?.Value
        dependentOn       = $_.PSObject.Properties['dependentOn']?.Value
        dependedOnBy      = $_.PSObject.Properties['dependedOnBy']?.Value
    }
}

$Categorised = @($collection | Where-Object { $_.categoryName }).Count
Write-Host "Settings with a category name: $Categorised of $($collection.Count)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Write output files
# ---------------------------------------------------------------------------
# Depth 5 was enough when a record was a name and a flat option list. The construction metadata
# nests further - options carry an optionValue which carries its own template reference - and
# ConvertTo-Json truncates silently past its depth rather than failing, so this is set well clear
# of what the deepest record actually needs.
$json = $collection | ConvertTo-Json -Depth 15 -Compress

# Backend Config (used by Compare-CIPPIntuneObject.ps1 at runtime)
$apiPath = Join-Path $PSScriptRoot '..\..\backend\Config\intuneCollection.json'
$json | Set-Content -Path $apiPath -Encoding utf8NoBOM
Write-Host "Written: $(Resolve-Path $apiPath)" -ForegroundColor Green

# The whole catalog in public/ as well. The UI reads the per-definition files and the search index
# rather than this, so nothing fetches it today - it is kept deliberately, as the complete catalog in
# a form anything in the browser can reach without going through either of those. Kept in step rather
# than left to go stale, so whatever does reach for it gets current data.
$frontendPath = Join-Path $PSScriptRoot '..\..\frontend\public\intuneCollection.json'
if (Test-Path (Split-Path $frontendPath)) {
    $json | Set-Content -Path $frontendPath -Encoding utf8NoBOM
    Write-Host "Written: $(Resolve-Path $frontendPath)" -ForegroundColor Green
}

# The category tree, kept whole in both places. A few hundred KB rather than the catalog's 18MB, so
# unlike the settings themselves this is small enough to ship as one file and needs no splitting.
if ($categories.Count -gt 0) {
    $categoryJson = $categories | ConvertTo-Json -Depth 5 -Compress

    $categoryApiPath = Join-Path $PSScriptRoot '..\..\backend\Config\intuneCategories.json'
    $categoryJson | Set-Content -Path $categoryApiPath -Encoding utf8NoBOM
    Write-Host "Written: $(Resolve-Path $categoryApiPath)" -ForegroundColor Green

    $categoryFrontendPath = Join-Path $PSScriptRoot '..\..\frontend\public\intuneCategories.json'
    if (Test-Path (Split-Path $categoryFrontendPath)) {
        $categoryJson | Set-Content -Path $categoryFrontendPath -Encoding utf8NoBOM
        Write-Host "Written: $(Resolve-Path $categoryFrontendPath)" -ForegroundColor Green
    }
}

# Frontend: one file per definition rather than the whole catalog. The UI fetches only the
# definitions a policy references - see Split-IntuneCollection.ps1 for why, and for the naming.
$splitScript = Join-Path $PSScriptRoot 'Split-IntuneCollection.ps1'
& $splitScript -CollectionPath $apiPath

Write-Host "`nDone. $($collection.Count) settings written to intuneCollection.json." -ForegroundColor Green
