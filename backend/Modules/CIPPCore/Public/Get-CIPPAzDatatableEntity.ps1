function Get-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Gets entities from an Azure Table, reassembling entities that were split for size.
    .DESCRIPTION
    Thin wrapper around Get-AzDataTableLargeEntity (AzBobbyTables >= 3.6.2), which
    natively merges rows that were split across multiple properties or rows because
    they exceeded the table service size limits.

    Kept as a wrapper for backward compatibility with existing call sites, to
    default MaxRetries to 3 for throttled requests, and to record entities the
    module could not reassemble.

    On TableNotFound, invalidates the CreateTable cache, recreates the table, and
    retries once so a stale CIPPEnsuredTables entry cannot permanently break reads.
    #>
    [CmdletBinding()]
    param(
        $Context,
        $Filter,
        $Property,
        $First,
        $Skip,
        $Sort,
        [switch]$Count,
        [int]$MaxRetries = 3
    )

    # ErrorAction and ErrorVariable are set below, so a caller that passed its own would collide
    # with the splat. Real errors are re-emitted afterwards, which honours the caller's preference.
    $Parameters = @{} + $PSBoundParameters
    $Parameters['MaxRetries'] = $MaxRetries
    $null = $Parameters.Remove('ErrorAction')
    $null = $Parameters.Remove('ErrorVariable')

    # A projection must always carry the row-level split metadata. Reassembly groups an entity's
    # rows by OriginalEntityId, identifies the master row by PartIndex and checks the set against
    # PartCount, so a caller that selects none of them leaves the module unable to tell a complete
    # entity from a truncated one - it reports every split entity as incomplete ("the first row of
    # the entity (PartIndex 0) was not returned") even though every row is present, and skips it.
    # Callers cannot act on entities they never see: Add-CIPPDbItem's orphan cleanup projects five
    # columns, so it never received the stale rows it exists to delete, and one uncollectable
    # generation accumulated per run.
    #
    # SplitOverProps is deliberately NOT added. It is the manifest for properties chunked across
    # Data_PartN columns, and JoinSplitProperties returns early when it is absent. Adding it makes
    # the module attempt the join, which throws IncompleteEntityException the moment a chunk column
    # is missing - and a projection that wants identity, not payload, never selects those columns.
    # That trades the row-level failure for a property-level one and skips the entity just the same.
    # A caller that needs the joined value must select the chunk columns, or project nothing at all.
    #
    # Requesting a property a row does not carry is harmless, so this is added unconditionally.
    if ($Parameters.ContainsKey('Property') -and $Parameters['Property']) {
        $SplitMetadata = @('PartIndex', 'PartCount', 'OriginalEntityId')
        $Parameters['Property'] = @(@($Parameters['Property']) + $SplitMetadata | Select-Object -Unique)
    }

    $Results = Get-AzDataTableLargeEntity @Parameters -ErrorAction SilentlyContinue -ErrorVariable TableErrors

    # Do not pipe $null/$empty into Where-Object - PowerShell invokes the block once with $_ = $null.
    $NotFoundErrors = [System.Collections.Generic.List[object]]::new()
    foreach ($Candidate in @($TableErrors)) {
        if ($null -ne $Candidate -and (Test-CIPPTableNotFound $Candidate)) {
            $NotFoundErrors.Add($Candidate)
        }
    }
    if ($NotFoundErrors.Count -and -not $script:CIPPRepairingTable) {
        $script:CIPPRepairingTable = $true
        try {
            Repair-CIPPTable -Context $Context
            $TableErrors = $null
            $Results = Get-AzDataTableLargeEntity @Parameters -ErrorAction SilentlyContinue -ErrorVariable TableErrors
        } finally {
            $script:CIPPRepairingTable = $false
        }
    }

    foreach ($TableError in $TableErrors) {
        # An entity whose rows cannot be reassembled is skipped by the module and reported without
        # failing the query, so one row orphaned by a pre-part-aware delete cannot empty a whole
        # partition. Record which row so it can be removed; pass everything else through.
        if ($TableError.FullyQualifiedErrorId -notlike 'IncompleteEntity*') {
            Write-Error -ErrorRecord $TableError
            continue
        }

        if (-not $script:ReportedIncompleteEntities) {
            $script:ReportedIncompleteEntities = [System.Collections.Generic.HashSet[string]]::new()
        }

        # Write-LogMessage reads a table itself, so logging here re-enters this function. The guard
        # stops that recursing, and the set reports each corrupt row once rather than on every read.
        $RowIdentity = "$($TableError.TargetObject)"
        if ($script:ReportingIncompleteEntity -or -not $script:ReportedIncompleteEntities.Add($RowIdentity)) {
            continue
        }

        $script:ReportingIncompleteEntity = $true
        try {
            Write-LogMessage -API 'Table' -message "Skipped a corrupt table entity. $($TableError.Exception.Message) Delete the orphaned '-partN' rows for '$RowIdentity' to clear this." -Sev 'Error'
        } finally {
            $script:ReportingIncompleteEntity = $false
        }
    }

    $Results
}
