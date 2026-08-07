function Get-CIPPIntuneCatalogIndex {
    <#
    .SYNOPSIS
        The shipped Intune setting catalog, indexed by settingDefinitionId.

    .DESCRIPTION
        Config\intuneCollection.json is the flattened Intune setting catalog that ships with the
        release - around 18,000 definitions, 19MB on disk. Reading and indexing it costs seconds, so
        the result is held for the life of the worker: a drift run or a bulk validation resolves
        thousands of ids against the same catalog and should pay for it once.

        Returns $null when the catalog is missing or unreadable. Callers treat the lookup as optional
        and skip catalog-dependent checks rather than failing - the catalog is a convenience for
        naming and sanity-checking settings, not something correctness depends on.

    .EXAMPLE
        $Catalog = Get-CIPPIntuneCatalogIndex
        if ($Catalog -and -not $Catalog.ContainsKey($Id)) { 'unknown setting' }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:CIPPIntuneCatalogIndex) {
        return $script:CIPPIntuneCatalogIndex
    }

    # A previous attempt that found nothing is remembered too, so a deployment without the catalog
    # does not re-read a missing file on every template it validates.
    if ($script:CIPPIntuneCatalogIndexTried) {
        return $null
    }
    $script:CIPPIntuneCatalogIndexTried = $true

    if ([string]::IsNullOrWhiteSpace($env:CIPPRootPath)) {
        Write-Information 'Intune catalog lookup skipped: CIPPRootPath is not set.'
        return $null
    }

    $CatalogPath = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config/intuneCollection.json'
    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        Write-Information "Intune catalog lookup skipped: $CatalogPath not found."
        return $null
    }

    try {
        $Catalog = Get-Content -LiteralPath $CatalogPath -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 20 -ErrorAction Stop
        $Index = @{}
        foreach ($Entry in $Catalog) {
            if ($Entry.id) { $Index[$Entry.id] = $Entry }
        }
        Write-Information "Intune catalog indexed: $($Index.Count) settings."
        $script:CIPPIntuneCatalogIndex = $Index
        return $Index
    } catch {
        Write-Information "Intune catalog could not be read: $($_.Exception.Message)"
        return $null
    }
}
