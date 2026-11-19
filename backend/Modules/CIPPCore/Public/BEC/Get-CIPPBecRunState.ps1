function Get-CIPPBecRunState {
    <#
    .SYNOPSIS
        Reads what the earlier phases of a BEC investigation collected.
    .DESCRIPTION
        Returns one hashtable of every value the phases saved with Set-CIPPBecRunState, applied in
        phase order so a later phase's value (rows re-saved with their IP verdicts, for one) wins.
        Each phase's Completeness markers are merged into one ordered Completeness dictionary.
        -Name reads only those values: the others are never built, so a phase does not pay for the
        large rows (sign-ins, mail records) it does not use.

        A section too large for one table property is a head row plus part rows, which are joined
        here before the JSON is parsed. A section whose parts are missing is reported as incomplete
        rather than returned partially, so a phase never mistakes a broken hand-off for empty data.
        Part rows from a superseded generation are ignored; -Clear removes them with the case.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string[]]$Name
    )

    $Table = Get-CIPPTable -TableName 'BecRunState'
    $State = @{}
    $Completeness = [ordered]@{}
    $Fields = if ($Name) { [string[]]@(@($Name) + 'Completeness') } else { $null }

    $Heads = @{}
    $Parts = @{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($CaseId -replace "'", "''")'" -ErrorAction Stop)) {
        if (-not $Row.Data) { continue }
        $RowKey = [string]$Row.RowKey
        if ($RowKey -notmatch '^(?<Section>.+)~(?<Generation>[0-9a-f]{32})~(?<Index>\d{4,})$') {
            $Heads[$RowKey] = $Row
            continue
        }
        $Key = "$($Matches.Section)|$($Matches.Generation)"
        if (-not $Parts.ContainsKey($Key)) { $Parts[$Key] = [System.Collections.Generic.List[object]]::new() }
        $Parts[$Key].Add($Row)
    }

    foreach ($Section in @($Heads.Keys | Sort-Object)) {
        $Head = $Heads[$Section]
        $ChunkCount = if ($null -ne $Head.ChunkCount) { [int]$Head.ChunkCount } else { 1 }
        $Pieces = [System.Collections.Generic.List[string]]::new()
        $Pieces.Add([string]$Head.Data)
        if ($ChunkCount -gt 1) {
            $Key = "$Section|$([string]$Head.Generation)"
            $SectionParts = @()
            if ($Parts.ContainsKey($Key)) { $SectionParts = @($Parts[$Key] | Sort-Object -Property ChunkIndex) }
            if ($SectionParts.Count -ne ($ChunkCount - 1)) {
                throw "BEC run state $Section is incomplete: expected $($ChunkCount - 1) part row(s), found $($SectionParts.Count)"
            }
            foreach ($Index in 1..($ChunkCount - 1)) {
                $Part = $SectionParts[$Index - 1]
                if ([int]$Part.ChunkIndex -ne $Index) {
                    throw "BEC run state $Section is incomplete: part $Index is missing"
                }
                $Pieces.Add([string]$Part.Data)
            }
        }
        $Values = [CIPP.CippJson]::ConvertFromJson((-join $Pieces), $Fields)
        foreach ($Property in $Values.PSObject.Properties) {
            if ($Property.Name -eq 'Completeness') {
                foreach ($Marker in @($Property.Value.PSObject.Properties)) { $Completeness[$Marker.Name] = $Marker.Value }
            } else {
                $State[$Property.Name] = $Property.Value
            }
        }
    }
    $State.Completeness = $Completeness
    return $State
}
