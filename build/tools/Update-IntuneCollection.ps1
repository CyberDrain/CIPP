<#
.SYNOPSIS
    Regenerates the Intune setting catalog lookup files from the Microsoft Graph API.

.DESCRIPTION
    Queries the Microsoft Graph beta endpoints for all Intune device management
    configuration setting definitions and their categories, then writes:

      backend\Config\intuneCollection.json     the whole catalog, read by
                                               Compare-CIPPIntuneObject.ps1 at runtime
      backend\Config\intuneCategories.json     the category records, whole
      frontend\public\intune-definitions\      256 bucket bundles of setting definitions,
                                               which is what the UI fetches (see
                                               Split-IntuneCollection.ps1 for why)
      frontend\public\intuneCategories.json    the category records, whole
      frontend\public\intune-templates\        one file per configuration policy template with
                                               its setting templates, plus index.json

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
    # Assigned inside the branch: an if-statement's output is enumerated, so a one-option array would
    # be written out as a bare object.
    $options = $null
    if ($rawOptions -and $rawOptions.Count -gt 0) {
        $options = @($rawOptions | ForEach-Object {
            [PSCustomObject]@{
                id           = $_.PSObject.Properties['itemId']?.Value
                displayName  = $_.PSObject.Properties['displayName']?.Value
                description  = $_.PSObject.Properties['description']?.Value
                helpText     = $_.PSObject.Properties['helpText']?.Value
                optionValue  = $_.PSObject.Properties['optionValue']?.Value
                dependentOn  = $_.PSObject.Properties['dependentOn']?.Value
                dependedOnBy = $_.PSObject.Properties['dependedOnBy']?.Value
            }
        })
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
        minimumCount = $_.PSObject.Properties['minimumCount']?.Value
        maximumCount = $_.PSObject.Properties['maximumCount']?.Value

        # Construction fields: what the template picker needs to build a setting from nothing.
        # Frontend bundles only - the backend file stays lean because every worker parses it.
        '@odata.type'    = $_.PSObject.Properties['@odata.type']?.Value
        valueDefinition  = $_.PSObject.Properties['valueDefinition']?.Value
        defaultOptionId  = $_.PSObject.Properties['defaultOptionId']?.Value
        applicability    = $_.PSObject.Properties['applicability']?.Value
        settingUsage     = $_.PSObject.Properties['settingUsage']?.Value
        visibility       = $_.PSObject.Properties['visibility']?.Value
        rootDefinitionId = $_.PSObject.Properties['rootDefinitionId']?.Value
        childIds         = $_.PSObject.Properties['childIds']?.Value
        dependentOn      = $_.PSObject.Properties['dependentOn']?.Value
        dependedOnBy     = $_.PSObject.Properties['dependedOnBy']?.Value
    }
}

$Categorised = @($collection | Where-Object { $_.categoryName }).Count
Write-Host "Settings with a category name: $Categorised of $($collection.Count)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Write output files
# ---------------------------------------------------------------------------
$json = $collection |
    Select-Object id, displayName, description, helpText, infoUrls, categoryId, categoryName, @{ n = 'options'; e = {
            if ($_.options) {
                , @(foreach ($Option in $_.options) {
                        $Slim = [ordered]@{ id = $Option.id; displayName = $Option.displayName; description = $Option.description; helpText = $Option.helpText }
                        # Only where present: validation needs them, and every worker parses this file.
                        $Required = @(@($Option.dependedOnBy).Where({ $_.required }).ForEach({ $_.dependedOnBy }))
                        if ($Required.Count -gt 0) { $Slim.requiredChildIds = $Required }
                        [pscustomobject]$Slim
                    })
            }
        }
    }, minimumCount, maximumCount |
    ConvertTo-Json -Depth 5 -Compress
$fullJsonPath = Join-Path ([System.IO.Path]::GetTempPath()) 'intuneCollection.full.json'
$collection | ConvertTo-Json -Depth 15 -Compress | Set-Content -Path $fullJsonPath -Encoding utf8NoBOM

# Backend Config (used by Compare-CIPPIntuneObject.ps1 at runtime)
$apiPath = Join-Path $PSScriptRoot '..\..\backend\Config\intuneCollection.json'
$json | Set-Content -Path $apiPath -Encoding utf8NoBOM
Write-Host "Written: $(Resolve-Path $apiPath)" -ForegroundColor Green

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

# Frontend: 256 bucket bundles rather than the whole catalog. The UI fetches only the buckets a
# policy references - see Split-IntuneCollection.ps1 for why, and for the naming.
$splitScript = Join-Path $PSScriptRoot 'Split-IntuneCollection.ps1'
& $splitScript -CollectionPath $fullJsonPath
Remove-Item -LiteralPath $fullJsonPath

# Template setting ids are the same in every tenant. Own folder: Split-IntuneCollection replaces intune-definitions wholesale.
Write-Host 'Fetching configuration policy templates...' -ForegroundColor Yellow

$templates = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates' -tenantid $TenantId -NoAuthCheck $true
$templatePath = Join-Path $PSScriptRoot '..\..\frontend\public\intune-templates'
if (Test-Path $templatePath) {
    Remove-Item -Path $templatePath -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $templatePath -Force

$templateIndex = foreach ($template in ($templates | Sort-Object -Property id)) {
    try {
        $settingTemplates = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates('$($template.id)')/settingTemplates" -tenantid $TenantId -NoAuthCheck $true)
    } catch {
        Write-Host "Could not fetch setting templates for $($template.id): $($_.Exception.Message)" -ForegroundColor Yellow
        continue
    }
    $template | Select-Object -Property *
    $template | Add-Member -NotePropertyName 'settingTemplates' -NotePropertyValue $settingTemplates -Force
    ConvertTo-Json -InputObject $template -Depth 40 -Compress | Set-Content -Path (Join-Path $templatePath "$($template.id).json") -Encoding utf8NoBOM
}
ConvertTo-Json -InputObject @($templateIndex) -Depth 5 -Compress | Set-Content -Path (Join-Path $templatePath 'index.json') -Encoding utf8NoBOM
Write-Host "Written: $(@($templateIndex).Count) of $(@($templates).Count) policy templates to $(Resolve-Path $templatePath)" -ForegroundColor Green

Write-Host "`nDone. $($collection.Count) settings written to intuneCollection.json." -ForegroundColor Green
