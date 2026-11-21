function Receive-CIPPCloudBackupObjectStream {
    <#
    .SYNOPSIS
        Downloads an object (or one version of it) from a cloud backup destination into a stream in bounded ranges.
    .DESCRIPTION
        Returns { Key; VersionId; Bytes; ContentType; Metadata }, or $null when the object or version does not exist.
        The data is written as stored; decrypting it is the caller's job. With -Offset / -Length only that range is
        written; Bytes is always the object's full size.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$VersionId,

        [ValidateRange(0, [long]::MaxValue)]
        [long]$Offset = 0,

        [ValidateRange(-1, [long]::MaxValue)]
        [long]$Length = [long]::MaxValue,

        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$OutStream
    )

    switch ($Destination.Provider) {
        'AzureBlob' { Receive-CIPPCloudBackupAzureObjectStream @PSBoundParameters }
        'S3' { Receive-CIPPCloudBackupS3ObjectStream @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
