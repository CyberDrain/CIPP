function Set-CIPPCloudBackupJsonl {
    <#
    .SYNOPSIS
        Stores objects as one gzip JSON-lines object in a cloud backup destination, encrypted as CIPPENC2 when a key is given.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [string]$KeyId,

        [byte[]]$EncryptionKey
    )

    if (-not $PSCmdlet.ShouldProcess($Key, 'Upload')) { return }

    $Buffer = [System.IO.MemoryStream]::new()
    try {
        $Gzip = [System.IO.Compression.GZipStream]::new($Buffer, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        $Writer = [System.IO.StreamWriter]::new($Gzip, [System.Text.UTF8Encoding]::new($false))
        foreach ($Item in $Items) {
            if ($null -eq $Item) { continue }
            $Writer.Write(([CIPP.CippJson]::ToJson($Item, 10) ?? (ConvertTo-Json -InputObject $Item -Depth 10 -Compress)))
            $Writer.Write("`n")
        }
        $Writer.Dispose()
        $Buffer.Position = 0
        $Params = @{ Destination = $Destination; Key = $Key; Stream = $Buffer; ContentType = 'application/gzip' }
        if ($KeyId) {
            $Params.KeyId = $KeyId
            $Params.EncryptionKey = $EncryptionKey
        }
        Send-CIPPCloudBackupObjectStream @Params
    } finally {
        $Buffer.Dispose()
    }
}
