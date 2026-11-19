function Set-CIPPBecRunState {
    <#
    .SYNOPSIS
        Saves what one phase of a BEC investigation collected, for the phases after it.
    .DESCRIPTION
        Every phase of a run is its own job, so what a phase collects is handed to the later ones
        through the BecRunState table: one row per phase (PartitionKey = case id, RowKey = the
        phase's order and key) holding its values as JSON. Get-CIPPBecRunState reads them back.
        -Clear deletes every row of the case (the start of a run and the end of the last phase).

        A value larger than one table property can hold (the Activity phase's raw mailbox records
        are the usual case) is written as a head row plus numbered part rows. Every row stays well
        inside the 64 KiB property limit, so the hand-off does not depend on the table module's own
        entity splitting. The head row is written last and names the generation, so a read never
        sees a half-written section and a failed attempt leaves the previous value in place. A
        superseded generation is left for -Clear rather than deleted here, so a reader never loses
        the parts of the head it is already following.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string]$Section,
        [hashtable]$Values,
        [switch]$Clear
    )

    # 24000 characters is 48 KiB of UTF-16, comfortably below the service's 64 KiB property limit
    # and below the 32K-character limit the service reports for a string property.
    $MaxChunkChars = 24000

    $Table = Get-CIPPTable -TableName 'BecRunState'
    if (-not $PSCmdlet.ShouldProcess($CaseId, $(if ($Clear) { 'Clear BEC run state' } else { "Save BEC run state $Section" }))) { return }
    if ($Clear) {
        # key-only projection: raw head and part rows, which the remover deletes without reassembly
        $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($CaseId -replace "'", "''")'" -Property PartitionKey, RowKey -ErrorAction Stop)
        if ($Rows.Count -gt 0) { $null = Remove-CIPPAzDataTableEntity @Table -Entity $Rows -Force }
        return
    }
    $Data = [CIPP.CippJson]::ToJson($Values, 20)
    if ($null -eq $Data) { throw "BEC run state $Section holds a value that cannot be written as JSON" }

    if ($Data.Length -le $MaxChunkChars) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = $CaseId
            RowKey       = $Section
            Data         = $Data
        } -Force
        return
    }

    # Split on a character boundary, never between a surrogate pair: the table stores UTF-16, and
    # half a pair would serialise as two replacement characters when the chunks are joined.
    $Chunks = [System.Collections.Generic.List[string]]::new()
    $Offset = 0
    while ($Offset -lt $Data.Length) {
        $Length = [Math]::Min($MaxChunkChars, $Data.Length - $Offset)
        if (($Offset + $Length) -lt $Data.Length -and [char]::IsHighSurrogate($Data[$Offset + $Length - 1])) { $Length-- }
        $Chunks.Add($Data.Substring($Offset, $Length))
        $Offset = $Offset + $Length
    }

    $Generation = [guid]::NewGuid().ToString('N')
    $ChunkCount = $Chunks.Count
    $PartRows = foreach ($Index in 1..($ChunkCount - 1)) {
        @{
            PartitionKey = $CaseId
            RowKey       = '{0}~{1}~{2:D4}' -f $Section, $Generation, $Index
            Data         = $Chunks[$Index]
            ChunkIndex   = $Index
            ChunkCount   = $ChunkCount
            Generation   = $Generation
        }
    }
    # Parts first, head last: the head is the commit marker the reader follows.
    Add-CIPPAzDataTableEntity @Table -Entity @($PartRows) -Force
    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = $CaseId
        RowKey       = $Section
        Data         = $Chunks[0]
        ChunkCount   = $ChunkCount
        Generation   = $Generation
    } -Force
}
