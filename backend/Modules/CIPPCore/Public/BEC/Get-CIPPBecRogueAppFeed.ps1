function Get-CIPPBecRogueAppFeed {
    <#
    .SYNOPSIS
        Returns the merged rogue-application catalog (CIPP MaliciousApps.json + Huntress rogueapps) keyed by appId.
    .DESCRIPTION
        The Huntress feed (https://huntresslabs.github.io/rogueapps/rogueapps.json) is fetched with a
        short timeout and cached for MaxAgeHours in the BecRogueAppFeed table and in a per-worker memo,
        so bulk BEC runs do not hit GitHub Pages once per user. CIPP's own curated list is always
        merged in; when the feed is unavailable the result says so (HuntressAvailable = $false) and the
        curated list alone is used - a feed outage must never fail a run or read as "no rogue apps".
    .PARAMETER MaxAgeHours
        Cache lifetime for the Huntress feed.
    .PARAMETER Force
        Ignore the caches and refetch.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [int]$MaxAgeHours = 24,
        [switch]$Force
    )

    $Now = (Get-Date).ToUniversalTime()
    if (-not $Force -and $script:CippBecRogueAppMemo -and $script:CippBecRogueAppMemo.Expires -gt $Now) {
        return $script:CippBecRogueAppMemo.Feed
    }

    $Apps = @{}
    $HuntressAvailable = $false
    $HuntressUpdated = $null
    $HuntressApps = @()

    # Table cache first, then the live feed.
    $Table = Get-CIPPTable -TableName 'BecRogueAppFeed'
    $Cached = $null
    if (-not $Force) {
        try {
            $Cached = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Feed' and RowKey eq 'Huntress'"
        } catch { $Cached = $null }
    }
    if ($Cached -and $Cached.Updated -and ([datetime]$Cached.Updated).ToUniversalTime().AddHours($MaxAgeHours) -gt $Now -and $Cached.Json) {
        try {
            $HuntressApps = @($Cached.Json | ConvertFrom-Json -ErrorAction Stop)
            $HuntressAvailable = $HuntressApps.Count -gt 0
            $HuntressUpdated = $Cached.Updated
        } catch { $HuntressApps = @() }
    }
    if (-not $HuntressAvailable) {
        try {
            $Feed = Invoke-RestMethod -Uri 'https://huntresslabs.github.io/rogueapps/rogueapps.json' -TimeoutSec 10 -ErrorAction Stop
            # A GitHub Pages error page parses without throwing, so check the shape too.
            if (@($Feed).Where({ $_.appId }, 'First')) {
                $HuntressApps = @($Feed | Where-Object { $_.appId } | Select-Object appId, appDisplayName, description, tags, references, dateAdded)
                $HuntressAvailable = $true
                $HuntressUpdated = $Now.ToString('o')
                try {
                    Add-CIPPAzDataTableEntity @Table -Entity @{
                        PartitionKey = 'Feed'
                        RowKey       = 'Huntress'
                        Updated      = $HuntressUpdated
                        Json         = [string](ConvertTo-Json -InputObject $HuntressApps -Depth 5 -Compress)
                    } -Force
                } catch {
                    Write-Information "BEC rogue app feed: could not cache the Huntress feed: $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Information "BEC rogue app feed: Huntress feed unavailable: $($_.Exception.Message)"
        }
    }

    foreach ($App in $HuntressApps) {
        if (-not $App.appId) { continue }
        $Apps[([string]$App.appId).ToLowerInvariant()] = [pscustomobject]@{
            Name        = $App.appDisplayName
            Description = $App.description
            Categories  = @()
            Tags        = @($App.tags)
            References  = @($App.references)
            Added       = $App.dateAdded
            Source      = 'Huntress'
        }
    }

    try {
        $CippApps = @((Get-Content -Path (Join-Path $env:CIPPRootPath 'Config\MaliciousApps.json') -ErrorAction Stop | ConvertFrom-Json).applications)
        foreach ($App in $CippApps) {
            if (-not $App.appId) { continue }
            $Key = ([string]$App.appId).ToLowerInvariant()
            # CIPP's entries carry categories and richer descriptions; they win over the feed copy.
            $Apps[$Key] = [pscustomobject]@{
                Name        = $App.name
                Description = $App.description
                Categories  = @($App.categories)
                Tags        = @($App.tags)
                References  = @($App.references)
                Added       = $null
                Source      = if ($Apps.ContainsKey($Key)) { 'CIPP, Huntress' } else { 'CIPP' }
            }
        }
    } catch {
        Write-Information "BEC rogue app feed: could not load MaliciousApps.json: $($_.Exception.Message)"
    }

    $Result = [pscustomobject]@{
        Apps              = $Apps
        Count             = $Apps.Count
        HuntressAvailable = [bool]$HuntressAvailable
        HuntressUpdated   = $HuntressUpdated
    }
    $script:CippBecRogueAppMemo = @{ Feed = $Result; Expires = $Now.AddHours(1) }
    return $Result
}
