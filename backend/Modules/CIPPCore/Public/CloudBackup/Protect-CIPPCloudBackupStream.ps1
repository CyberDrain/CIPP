function Protect-CIPPCloudBackupStream {
    <#
    .SYNOPSIS
        Encrypts a stream into another stream in the chunked CIPPENC2 format and returns the number of bytes written.
    .DESCRIPTION
        The format is described in Read-CIPPCloudBackupStreamBlock. Memory use is bounded by the chunk size.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$InputStream,

        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$OutputStream,

        [Parameter(Mandatory = $true)]
        [string]$KeyId,

        [Parameter(Mandatory = $true)]
        [byte[]]$Key,

        [ValidateRange(1, 64MB)]
        [int]$ChunkSize = 4MB
    )

    $Reader = @{ Stream = $InputStream; KeyId = $KeyId; Key = $Key; ChunkSize = $ChunkSize }
    $Written = [long]0
    do {
        $Block = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 1MB
        $OutputStream.Write($Block, 0, $Block.Length)
        $Written += $Block.Length
    } while ($Block.Length -eq 1MB)
    return $Written
}
