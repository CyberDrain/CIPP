function Save-CIPPCloudBackupJobManifest {
    <#
    .SYNOPSIS
        Resolves a restore or export selection at the job's point in time and stores it as the job's item manifest.
    .DESCRIPTION
        Selects the owner's items at Context.RunStamp by key (-Keys, deleted items included so they can be restored)
        and by folder (-Paths, everything below them including folder entries); with neither, every item and folder of
        the owner. Entries are streamed from Get-CIPPCloudBackupOwnerListing into parts of 500 at
        <policyId>/jobs/<jobId>/items/<nnnnn>.jsonl.gz(.enc), encrypted when the context has a key, and an entry
        selected twice is written once. Returns { Items; Parts }. Get-CIPPCloudBackupJobItemBatch reads them back.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [string[]]$Keys,

        [string[]]$Paths
    )

    $PartSize = 500
    $KeyList = [string[]]@(foreach ($Key in @($Keys)) { if ($Key) { $Key } })
    $PathList = [System.Collections.Generic.List[string]]::new()
    $All = $false
    foreach ($Path in @($Paths)) {
        if ($null -eq $Path) { continue }
        $Trimmed = $Path.Trim('/')
        if ($Trimmed) { $PathList.Add($Trimmed) } else { $All = $true }
    }
    if ($KeyList.Count -eq 0 -and $PathList.Count -eq 0) { $All = $true }

    $Suffix = if ($Context.KeyId) { '.enc' } else { '' }
    $WriteParams = @{ Destination = $Context.Destination }
    if ($Context.KeyId) {
        $WriteParams.KeyId = $Context.KeyId
        $WriteParams.EncryptionKey = $Context.Key
    }
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $Buffer = [System.Collections.Generic.List[object]]::new($PartSize)
    $Counter = @{ Items = 0; Parts = 0 }
    $Write = $PSCmdlet.ShouldProcess($Context.JobId, 'Write job manifest')
    $Collect = {
        process {
            if ($null -eq $_ -or -not $Seen.Add([string]$_.Key)) { return }
            $Buffer.Add([pscustomobject]@{
                    Key       = $_.Key
                    Path      = $_.Path
                    Name      = $_.Name
                    Type      = $_.Type
                    Size      = $_.Size
                    Modified  = $_.Modified
                    VersionId = $_.VersionId
                    Deleted   = [bool]$_.Deleted
                    Extra     = $_.Extra
                    RunStamp  = $_.RunStamp
                })
            $Counter.Items++
            if ($Buffer.Count -ge $PartSize) {
                if ($Write) { $null = Set-CIPPCloudBackupJsonl @WriteParams -Key ('{0}/jobs/{1}/items/{2:D5}.jsonl.gz{3}' -f $Context.PolicyId, $Context.JobId, $Counter.Parts, $Suffix) -Items $Buffer.ToArray() -Confirm:$false }
                $Counter.Parts++
                $Buffer.Clear()
            }
        }
    }

    $Listing = @{ Destination = $Context.Destination; OwnerPrefix = $Context.OwnerPrefix; AsOf = $Context.RunStamp; Stream = $true }
    if ($All) {
        Get-CIPPCloudBackupOwnerListing @Listing -Recurse -IncludeFolders | & $Collect
    } else {
        if ($KeyList.Count -gt 0) { Get-CIPPCloudBackupOwnerListing @Listing -Key $KeyList -IncludeDeleted | & $Collect }
        foreach ($Path in $PathList) { Get-CIPPCloudBackupOwnerListing @Listing -Path $Path -Recurse -IncludeFolders | & $Collect }
    }
    $Parts = $Counter.Parts
    $Items = $Counter.Items
    if ($Buffer.Count -gt 0 -or $Parts -eq 0) {
        if ($Write) { $null = Set-CIPPCloudBackupJsonl @WriteParams -Key ('{0}/jobs/{1}/items/{2:D5}.jsonl.gz{3}' -f $Context.PolicyId, $Context.JobId, $Parts, $Suffix) -Items $Buffer.ToArray() -Confirm:$false }
        $Parts++
    }
    [pscustomobject]@{ Items = $Items; Parts = $Parts }
}
