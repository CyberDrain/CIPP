function Get-CIPPCloudBackupJobItemBatch {
    <#
    .SYNOPSIS
        Returns up to -Count listing entries of a restore or export job's item manifest, starting at -Offset.
    .DESCRIPTION
        The manifest is stored in parts of 500 entries under <policyId>/jobs/<jobId>/items/. Fewer entries than -Count
        means the end of the manifest was reached. The last part read is kept for the next call, so a step loop does not
        download the same part again.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Offset,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Count
    )

    $PartSize = 500
    $JobId = if ($Context.ManifestJobId) { $Context.ManifestJobId } else { $Context.JobId }
    $Suffix = if ($Context.KeyId) { '.enc' } else { '' }
    $Batch = [System.Collections.Generic.List[object]]::new()
    $Position = $Offset
    while ($Batch.Count -lt $Count) {
        $Part = [int][Math]::Floor($Position / $PartSize)
        $Key = '{0}/jobs/{1}/items/{2:D5}.jsonl.gz{3}' -f $Context.PolicyId, $JobId, $Part, $Suffix
        $Memo = $script:CIPPCloudBackupManifestPart
        $Entries = if ($Memo -and $Memo.Key -ceq $Key) {
            $Memo.Entries
        } else {
            $Read = Get-CIPPCloudBackupJsonl -Destination $Context.Destination -Key $Key
            $script:CIPPCloudBackupManifestPart = @{ Key = $Key; Entries = $Read }
            $Read
        }
        if ($null -eq $Entries) { break }
        $Start = $Position - ($Part * $PartSize)
        if ($Start -ge $Entries.Count) { break }
        for ($i = $Start; $i -lt $Entries.Count -and $Batch.Count -lt $Count; $i++) {
            $Entry = $Entries[$i]
            $Batch.Add([pscustomobject]@{
                    Key       = $Entry.Key
                    Path      = $Entry.Path
                    Name      = $Entry.Name
                    Type      = $Entry.Type
                    Size      = $Entry.Size
                    Modified  = $Entry.Modified
                    VersionId = $Entry.VersionId
                    Deleted   = [bool]$Entry.Deleted
                    Extra     = $Entry.Extra
                    RunStamp  = $Entry.RunStamp
                })
            $Position++
        }
        if ($Entries.Count -lt $PartSize) { break }
    }
    $Batch.ToArray()
}
