function Read-CIPPCloudBackupIndexState {
    <#
    .SYNOPSIS
        Replays index files in order into one slim record per item key; the last write of a key wins.
    .DESCRIPTION
        Returns a hashtable of parallel lists indexed by slot (Slots maps key -> slot): Keys, P (stored parent path,
        normalised), N (folders only), T, S (-1 = none), M (UTC ticks, 0 = none), D, R (RunStamp of the write),
        ParentId, Hit (-Search matched the name or sender/recipients), Src and Line (where the winning line is; item
        names, versions and Extra are read from it again for the entries returned). A delete of a known key keeps
        the last live record, so deleted items keep their name and the version to restore.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$OwnerPrefix,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Files,

        [string]$Search
    )

    $SharePoint = $OwnerPrefix.Split('/')[2] -eq 'sharepoint'
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase
    $State = @{
        Files    = $Files
        Slots    = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        Keys     = [System.Collections.Generic.List[string]]::new()
        P        = [System.Collections.Generic.List[string]]::new()
        N        = [System.Collections.Generic.List[string]]::new()
        T        = [System.Collections.Generic.List[string]]::new()
        S        = [System.Collections.Generic.List[long]]::new()
        M        = [System.Collections.Generic.List[long]]::new()
        D        = [System.Collections.Generic.List[bool]]::new()
        R        = [System.Collections.Generic.List[string]]::new()
        ParentId = [System.Collections.Generic.List[string]]::new()
        Hit      = [System.Collections.Generic.List[bool]]::new()
        Src      = [System.Collections.Generic.List[int]]::new()
        Line     = [System.Collections.Generic.List[int]]::new()
    }
    $Slots = $State.Slots
    $Pool = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $Pool[''] = ''
    $Parsed = [datetime]::MinValue
    $Styles = [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal'
    $Interned = $null

    for ($Src = 0; $Src -lt $Files.Count; $Src++) {
        $File = $Files[$Src]
        $FileStamp = [string]$File.RunStamp
        $Reader = Open-CIPPCloudBackupIndexReader -Destination $Destination -Key $File.Key
        try {
            $LineNo = -1
            while ($null -ne ($Text = $Reader.ReadLine())) {
                $LineNo++
                if (-not $Text) { continue }
                $E = [CIPP.CippJson]::ConvertFromJson($Text)
                $K = [string]$E.k
                if (-not $K) { continue }
                $Deleted = [bool]$E.d
                $Stamp = $FileStamp
                if ($File.Snapshot -and $E.r) {
                    $Stamp = [string]$E.r
                    if ($Pool.TryGetValue($Stamp, [ref]$Interned)) { $Stamp = $Interned } else { $Pool[$Stamp] = $Stamp }
                }

                $Slot = -1
                $Known = $Slots.TryGetValue($K, [ref]$Slot)
                if ($Known -and $Deleted) {
                    if (-not $State.D[$Slot]) {
                        $State.D[$Slot] = $true
                        $State.R[$Slot] = $Stamp
                    }
                    continue
                }

                $X = $E.x
                $PathText = ([string]$E.p).Trim('/')
                if ($SharePoint -and $X.driveName) {
                    $PathText = if ($PathText) { "$($X.driveName)/$PathText" } else { [string]$X.driveName }
                }
                if ($Pool.TryGetValue($PathText, [ref]$Interned)) { $PathText = $Interned } else { $Pool[$PathText] = $PathText }
                $Type = [string]$E.t
                if ($Pool.TryGetValue($Type, [ref]$Interned)) { $Type = $Interned } else { $Pool[$Type] = $Type }
                $ParentId = if ($X) { [string]$X.parentId } else { '' }
                if ($Pool.TryGetValue($ParentId, [ref]$Interned)) { $ParentId = $Interned } else { $Pool[$ParentId] = $ParentId }
                $Name = if ($null -eq $E.n) { $null } else { [string]$E.n }
                $Size = if ($null -eq $E.s) { [long]-1 } else { [long]$E.s }
                $Ticks = [long]0
                $Modified = $E.m
                if ($Modified -is [datetime]) {
                    $Ticks = if ($Modified.Kind -eq [System.DateTimeKind]::Local) { $Modified.ToUniversalTime().Ticks } else { $Modified.Ticks }
                } elseif ($Modified -and [datetime]::TryParse([string]$Modified, [cultureinfo]::InvariantCulture, $Styles, [ref]$Parsed)) {
                    $Ticks = $Parsed.Ticks
                }
                $Hit = $false
                if ($Search) {
                    $Hit = ($Name -and $Name.IndexOf($Search, $Comparison) -ge 0) -or
                    ($X.from -and ([string]$X.from).IndexOf($Search, $Comparison) -ge 0) -or
                    ($X.to -and ([string]$X.to).IndexOf($Search, $Comparison) -ge 0)
                }
                $StoredName = if ($Type -eq 'folder') { $Name } else { $null }

                if ($Known) {
                    $State.P[$Slot] = $PathText
                    $State.N[$Slot] = $StoredName
                    $State.T[$Slot] = $Type
                    $State.S[$Slot] = $Size
                    $State.M[$Slot] = $Ticks
                    $State.D[$Slot] = $Deleted
                    $State.R[$Slot] = $Stamp
                    $State.ParentId[$Slot] = $ParentId
                    $State.Hit[$Slot] = $Hit
                    $State.Src[$Slot] = $Src
                    $State.Line[$Slot] = $LineNo
                } else {
                    $Slots[$K] = $State.Keys.Count
                    $State.Keys.Add($K)
                    $State.P.Add($PathText)
                    $State.N.Add($StoredName)
                    $State.T.Add($Type)
                    $State.S.Add($Size)
                    $State.M.Add($Ticks)
                    $State.D.Add($Deleted)
                    $State.R.Add($Stamp)
                    $State.ParentId.Add($ParentId)
                    $State.Hit.Add($Hit)
                    $State.Src.Add($Src)
                    $State.Line.Add($LineNo)
                }
            }
        } finally {
            $Reader.Dispose()
        }
    }
    $State
}
