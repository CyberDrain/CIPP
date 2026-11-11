<#
.SYNOPSIS
    Regenerates the Global Secure Access web category list from the Microsoft Graph API.

.DESCRIPTION
    Reads beta/networkAccess/connectivity/webCategories and writes
    frontend\src\data\GSAWebCategories.json, the list the filtering policy template editor
    offers. Each entry keeps the Graph shape: name (the value a webCategory destination
    takes), displayName and group. Deploys validate against the target tenant's live list,
    so this file only needs refreshing when Microsoft adds or retires a category.

.PARAMETER TenantId
    A CIPP-managed tenant that is onboarded to Global Secure Access. Every networkAccess
    path except tenantStatus answers 403 until the tenant is onboarded.

.EXAMPLE
    . .\Initialize-DevEnvironment.ps1
    .\Update-GSAWebCategories.ps1 -TenantId contoso.onmicrosoft.com

.NOTES
    Permissions required: NetworkAccess.Read.All (application)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -Name CIPPCore)) {
    . (Join-Path $PSScriptRoot 'Initialize-DevEnvironment.ps1')
}

$Categories = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/connectivity/webCategories' -tenantid $TenantId -AsApp $true |
        Sort-Object group, displayName |
        ForEach-Object { [ordered]@{ name = $_.name; displayName = $_.displayName; group = $_.group } })
if ($Categories.Count -eq 0) { throw "Graph returned no web categories for $TenantId" }

$OutFile = Join-Path $PSScriptRoot '..\..\frontend\src\data\GSAWebCategories.json'
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutFile), (ConvertTo-Json -InputObject $Categories -Depth 3).Replace("`r`n", "`n") + "`n")
Write-Host "Wrote $($Categories.Count) web categories to $OutFile"
