function Get-CIPPBecHeuristics {
    <#
    .SYNOPSIS
        Loads the BEC detection heuristics from Config\BecHeuristics.json.
    .DESCRIPTION
        Returns the parsed heuristics object (regexes, thresholds, caps and score weights) used by the
        BEC collectors and the server-side threat score. The file is memoised per worker and reloaded
        when its last-write time changes, so edits are picked up without a restart while a single run
        never pays for repeated parsing.

        When riskyScopes.includeRiskyPermissionsCatalog is true the delegated permission names from
        Config\RiskyPermissions.json are merged into riskyScopes.catalogNames so a grant is flagged by
        the curated catalog as well as by the regex.
    .PARAMETER Force
        Ignore the memo and reload from disk.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $Path = Join-Path $env:CIPPRootPath 'Config\BecHeuristics.json'
    $LastWrite = try { (Get-Item -Path $Path -ErrorAction Stop).LastWriteTimeUtc } catch { $null }

    if (-not $Force -and $script:CippBecHeuristicsMemo -and $script:CippBecHeuristicsMemo.Path -eq $Path -and $script:CippBecHeuristicsMemo.LastWrite -eq $LastWrite) {
        return $script:CippBecHeuristicsMemo.Heuristics
    }

    $Heuristics = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop

    # Merge the curated delegated-permission catalog so a grant is caught by name as well as by regex.
    $CatalogNames = @()
    if ($Heuristics.riskyScopes.includeRiskyPermissionsCatalog -eq $true) {
        try {
            $RiskyPermissions = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\RiskyPermissions.json')) | ConvertFrom-Json -ErrorAction Stop
            $CatalogNames = @($RiskyPermissions | Where-Object { $_.type -eq 'Delegated' -and $_.name } | ForEach-Object { $_.name } | Select-Object -Unique)
        } catch {
            Write-Information "BEC heuristics: could not merge RiskyPermissions.json: $($_.Exception.Message)"
        }
    }
    $Heuristics.riskyScopes | Add-Member -NotePropertyName 'catalogNames' -NotePropertyValue $CatalogNames -Force

    $script:CippBecHeuristicsMemo = @{
        Path       = $Path
        LastWrite  = $LastWrite
        Heuristics = $Heuristics
    }
    return $Heuristics
}
