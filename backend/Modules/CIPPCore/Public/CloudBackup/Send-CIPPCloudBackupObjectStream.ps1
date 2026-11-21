function Send-CIPPCloudBackupObjectStream {
    <#
    .SYNOPSIS
        Uploads a stream to a cloud backup destination without buffering it whole, and returns { Key; Bytes; VersionId; Size }.
    .DESCRIPTION
        Streams under 8 MiB are sent with one PUT; larger ones as Azure blocks or S3 multipart parts. With -KeyId and
        -EncryptionKey the stream is encrypted as CIPPENC2 while it is read. Bytes is the stored size, Size the size of the original content, and VersionId is
        $null when the destination does not version objects.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [string]$ContentType = 'application/octet-stream',

        [hashtable]$Metadata,

        [string]$KeyId,

        [byte[]]$EncryptionKey
    )

    if ([bool]$KeyId -ne ($null -ne $EncryptionKey)) {
        throw [System.ArgumentException]::new('Encryption needs both a key id and a key.')
    }
    if ($Destination.Provider -notin @('AzureBlob', 'S3')) {
        throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.")
    }

    $Reader = @{ Stream = $Stream; SourceBytes = [int64]0 }
    if ($KeyId) {
        $Reader.KeyId = $KeyId
        $Reader.Key = $EncryptionKey
    }

    $FirstBlock = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 8MB
    $Result = if ($FirstBlock.Length -lt 8MB) {
        Set-CIPPCloudBackupObject -Destination $Destination -Key $Key -Body $FirstBlock -ContentType $ContentType -Metadata $Metadata -Confirm:$false
    } else {
        $Params = @{ Destination = $Destination; Key = $Key; Reader = $Reader; FirstBlock = $FirstBlock; ContentType = $ContentType; Metadata = $Metadata }
        if ($Destination.Provider -eq 'AzureBlob') {
            Send-CIPPCloudBackupAzureObjectStream @Params
        } else {
            Send-CIPPCloudBackupS3ObjectStream @Params
        }
    }
    $Result.PSObject.Properties.Add([psnoteproperty]::new('Size', $Reader.SourceBytes))
    $Result
}
