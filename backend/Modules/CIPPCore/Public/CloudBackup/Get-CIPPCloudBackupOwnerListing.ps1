function Get-CIPPCloudBackupOwnerListing {
    <#
    .SYNOPSIS
        Lists an owner's backed-up items as they were at a point in time, with folder navigation, search and paging.
    .DESCRIPTION
        Replays the newest snapshot at or before the point in time and the index parts after it, up to that point.
        Returns { RunStamp; Total; Items; Folders }, newest Modified first. An item's Path is the folder that holds
        it; a Folders entry's Path is the folder's own path, the value to pass back as -Path. Paths are '/'-separated
        without leading or trailing '/', the root being ''. Without -Path every item of the owner is listed. With
        -Stream every matching entry is written to the pipeline instead (no paging, no sorting, no Folders).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$OwnerPrefix,

        $AsOf,

        [AllowEmptyString()]
        [string]$Path,

        [switch]$Recurse,

        [string]$Search,

        [string[]]$Type,

        [string[]]$Key,

        [datetime]$ModifiedFrom,

        [datetime]$ModifiedTo,

        [switch]$IncludeDeleted,

        [switch]$IncludeFolders,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Skip = 0,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Take = 100,

        [switch]$Stream
    )

    $AsOfTime = if ($null -eq $AsOf -or "$AsOf" -eq '') {
        [datetime]::MaxValue
    } elseif ($AsOf -is [datetime]) {
        if ($AsOf.Kind -eq [System.DateTimeKind]::Local) { $AsOf.ToUniversalTime() } else { $AsOf }
    } elseif ("$AsOf" -match '^\d{8}T\d{6}Z$') {
        [datetime]::ParseExact("$AsOf", "yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal')
    } else {
        $Parsed = [datetime]::MinValue
        if (-not [datetime]::TryParse("$AsOf", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$Parsed)) {
            throw [System.ArgumentException]::new("'$AsOf' is not a point in time.")
        }
        $Parsed
    }

    $AllFiles = @(Get-CIPPCloudBackupIndexFile -Destination $Destination -OwnerPrefix $OwnerPrefix)
    $RunStamp = $null
    $SnapshotStamp = $null
    foreach ($File in $AllFiles) {
        if ($File.At -gt $AsOfTime) { break }
        $RunStamp = $File.RunStamp
        if ($File.Snapshot) { $SnapshotStamp = $File.RunStamp }
    }
    if (-not $RunStamp) {
        if ($Stream) { return }
        return [pscustomobject]@{ RunStamp = $null; Total = 0; Items = @(); Folders = @() }
    }
    $Files = @(foreach ($File in $AllFiles) {
            if ([string]::CompareOrdinal($File.RunStamp, $RunStamp) -gt 0) { break }
            if ($SnapshotStamp) {
                if ([string]::CompareOrdinal($File.RunStamp, $SnapshotStamp) -lt 0) { continue }
                if ($File.Snapshot -and $File.RunStamp -ne $SnapshotStamp) { continue }
            } elseif ($File.Snapshot) {
                continue
            }
            $File
        })

    $State = Read-CIPPCloudBackupIndexState -Destination $Destination -OwnerPrefix $OwnerPrefix -Files $Files -Search $Search
    $Slots = $State.Slots
    $Count = $State.Keys.Count
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase
    $TypeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($T in @($Type)) { if ($T) { $null = $TypeSet.Add($T) } }
    $KeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($K in @($Key)) { if ($K) { $null = $KeySet.Add($K.TrimStart('/')) } }
    $WantFolders = $IncludeFolders -or $TypeSet.Contains('folder')
    $PathBound = $PSBoundParameters.ContainsKey('Path')
    $NormPath = "$Path".Trim('/')
    $ChildPrefix = if ($NormPath) { "$NormPath/" } else { '' }
    $FromTicks = if ($PSBoundParameters.ContainsKey('ModifiedFrom')) { $ModifiedFrom.ToUniversalTime().Ticks } else { [long]::MinValue }
    $ToTicks = if ($PSBoundParameters.ContainsKey('ModifiedTo')) { $ModifiedTo.ToUniversalTime().Ticks } else { [long]::MaxValue }

    $FolderPathMemo = [System.Collections.Generic.Dictionary[int, string]]::new()
    $Chain = [System.Collections.Generic.List[int]]::new()
    $Folders = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $PathBySlot = [string[]]::new($Count)
    $Selected = [System.Collections.Generic.List[int]]::new()
    $SelectedTicks = [System.Collections.Generic.List[long]]::new()
    $Known = $null
    $ParentSlot = -1

    for ($Slot = 0; $Slot -lt $Count; $Slot++) {
        if ($State.D[$Slot] -and -not $IncludeDeleted) { continue }
        if ($KeySet.Count -gt 0 -and -not $KeySet.Contains($State.Keys[$Slot])) { continue }
        $IsFolder = $State.T[$Slot] -eq 'folder'

        $Chain.Clear()
        $Cursor = $Slot
        $Base = $null
        $Resolved = $false
        for ($Depth = 0; $Depth -lt 64; $Depth++) {
            $CursorKey = $State.Keys[$Cursor]
            $ParentId = $State.ParentId[$Cursor]
            $ParentKey = if ($CursorKey.EndsWith('/')) {
                if ($ParentId) { 'items/{0}/' -f $ParentId.Replace('/', '-').Replace('+', '_') } else { $null }
            } else {
                $CursorKey.Substring(0, $CursorKey.LastIndexOf('/') + 1) + $ParentId
            }
            if (-not $ParentKey -or -not $Slots.TryGetValue($ParentKey, [ref]$ParentSlot) -or $ParentSlot -eq $Cursor -or $State.T[$ParentSlot] -ne 'folder') {
                $Base = $State.P[$Cursor]
                break
            }
            $Resolved = $true
            if ($FolderPathMemo.TryGetValue($ParentSlot, [ref]$Known)) {
                $Base = $Known
                break
            }
            $Chain.Add($ParentSlot)
            $Cursor = $ParentSlot
        }
        if ($null -eq $Base) { $Base = $State.P[$Cursor] }
        for ($i = $Chain.Count - 1; $i -ge 0; $i--) {
            $Base = if ($Base) { "$Base/$($State.N[$Chain[$i]])" } else { [string]$State.N[$Chain[$i]] }
            $FolderPathMemo[$Chain[$i]] = $Base
        }
        $ParentPath = $Base

        if (-not $Stream) {
            if ($IsFolder -and $ParentPath.Equals($NormPath, $Comparison)) {
                $OwnPath = if ($ParentPath) { "$ParentPath/$($State.N[$Slot])" } else { [string]$State.N[$Slot] }
                $Folders[[string]$State.N[$Slot]] = [pscustomobject]@{
                    Key = $State.Keys[$Slot]; Path = $OwnPath; Name = $State.N[$Slot]; Type = 'folder'; Size = $null; Modified = $null
                    VersionId = $null; Deleted = $State.D[$Slot]; Extra = $null; RunStamp = $State.R[$Slot]
                }
            } elseif (-not $Resolved -and $ParentPath.Length -gt $ChildPrefix.Length -and $ParentPath.StartsWith($ChildPrefix, $Comparison)) {
                $End = $ParentPath.IndexOf('/', $ChildPrefix.Length)
                $ChildName = if ($End -lt 0) { $ParentPath.Substring($ChildPrefix.Length) } else { $ParentPath.Substring($ChildPrefix.Length, $End - $ChildPrefix.Length) }
                if (-not $Folders.ContainsKey($ChildName)) {
                    $Folders[$ChildName] = [pscustomobject]@{
                        Key = $null; Path = "$ChildPrefix$ChildName"; Name = $ChildName; Type = 'folder'; Size = $null; Modified = $null
                        VersionId = $null; Deleted = $false; Extra = $null; RunStamp = $null
                    }
                }
            }
        }

        if ($IsFolder) {
            if (-not $WantFolders) { continue }
        } elseif ($TypeSet.Count -gt 0 -and -not $TypeSet.Contains($State.T[$Slot])) {
            continue
        }
        if ($PathBound) {
            if ($Recurse) {
                if ($NormPath -and -not $ParentPath.Equals($NormPath, $Comparison) -and -not $ParentPath.StartsWith($ChildPrefix, $Comparison)) { continue }
            } elseif (-not $ParentPath.Equals($NormPath, $Comparison)) {
                continue
            }
        }
        $Ticks = $State.M[$Slot]
        if ($Ticks -lt $FromTicks -or $Ticks -gt $ToTicks) { continue }
        if ($Search -and -not $State.Hit[$Slot] -and $ParentPath.IndexOf($Search, $Comparison) -lt 0) { continue }

        $PathBySlot[$Slot] = $ParentPath
        $Selected.Add($Slot)
        $SelectedTicks.Add($Ticks)
    }

    $Total = $Selected.Count
    $PageSlots = if ($Stream) {
        $Selected.ToArray()
    } else {
        $SortSlots = $Selected.ToArray()
        [System.Array]::Sort($SelectedTicks.ToArray(), $SortSlots)
        [System.Array]::Reverse($SortSlots)
        $PageCount = [Math]::Max(0, [Math]::Min($Take, $Total - $Skip))
        $Page = [int[]]::new($PageCount)
        if ($PageCount -gt 0) { [System.Array]::Copy($SortSlots, $Skip, $Page, 0, $PageCount) }
        $Page
    }

    $Order = [long[]]::new($PageSlots.Length)
    $OrderSlots = [int[]]::new($PageSlots.Length)
    for ($i = 0; $i -lt $PageSlots.Length; $i++) {
        $Order[$i] = ([long]$State.Src[$PageSlots[$i]] -shl 32) -bor [long]$State.Line[$PageSlots[$i]]
        $OrderSlots[$i] = $PageSlots[$i]
    }
    [System.Array]::Sort($Order, $OrderSlots)
    $Lines = [System.Collections.Generic.Dictionary[int, object]]::new()
    $Fields = [string[]]@('n', 'v', 'x')
    $Position = 0
    while ($Position -lt $Order.Length) {
        $Src = [int]($Order[$Position] -shr 32)
        $Reader = Open-CIPPCloudBackupIndexReader -Destination $Destination -Key $State.Files[$Src].Key
        try {
            $LineNo = -1
            while ($Position -lt $Order.Length -and [int]($Order[$Position] -shr 32) -eq $Src -and $null -ne ($Text = $Reader.ReadLine())) {
                $LineNo++
                if (($Order[$Position] -band 0xFFFFFFFFL) -ne $LineNo) { continue }
                $Slot = $OrderSlots[$Position]
                $Position++
                $Line = [CIPP.CippJson]::ConvertFromJson($Text, $Fields)
                if (-not $Stream) {
                    $Lines[$Slot] = $Line
                    continue
                }
                [pscustomobject]@{
                    Key       = $State.Keys[$Slot]
                    Path      = $PathBySlot[$Slot]
                    Name      = $Line.n
                    Type      = $State.T[$Slot]
                    Size      = if ($State.S[$Slot] -lt 0) { $null } else { $State.S[$Slot] }
                    Modified  = if ($State.M[$Slot] -eq 0) { $null } else { [datetime]::new($State.M[$Slot], [System.DateTimeKind]::Utc) }
                    VersionId = $Line.v
                    Deleted   = $State.D[$Slot]
                    Extra     = $Line.x
                    RunStamp  = $State.R[$Slot]
                }
            }
        } finally {
            $Reader.Dispose()
        }
        while ($Position -lt $Order.Length -and [int]($Order[$Position] -shr 32) -eq $Src) { $Position++ }
    }
    if ($Stream) { return }

    $Items = foreach ($Slot in $PageSlots) {
        $Line = $Lines[$Slot]
        [pscustomobject]@{
            Key       = $State.Keys[$Slot]
            Path      = $PathBySlot[$Slot]
            Name      = $Line.n
            Type      = $State.T[$Slot]
            Size      = if ($State.S[$Slot] -lt 0) { $null } else { $State.S[$Slot] }
            Modified  = if ($State.M[$Slot] -eq 0) { $null } else { [datetime]::new($State.M[$Slot], [System.DateTimeKind]::Utc) }
            VersionId = $Line.v
            Deleted   = $State.D[$Slot]
            Extra     = $Line.x
            RunStamp  = $State.R[$Slot]
        }
    }
    $FolderNames = [string[]]::new($Folders.PSBase.Count)
    $Folders.PSBase.Keys.CopyTo($FolderNames, 0)
    [System.Array]::Sort($FolderNames, [System.StringComparer]::OrdinalIgnoreCase)

    [pscustomobject]@{
        RunStamp = $RunStamp
        Total    = $Total
        Items    = @($Items)
        Folders  = @(foreach ($Name in $FolderNames) { $Folders[$Name] })
    }
}
