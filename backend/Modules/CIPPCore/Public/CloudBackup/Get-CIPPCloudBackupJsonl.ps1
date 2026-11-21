function Get-CIPPCloudBackupJsonl {
    <#
    .SYNOPSIS
        Reads a gzip JSON-lines object written by Set-CIPPCloudBackupJsonl, decrypting it when needed.
    .DESCRIPTION
        Returns the parsed objects as an array, or $null when the object does not exist. Meant for job manifests and
        results, which are written in small parts.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Stored = [System.IO.MemoryStream]::new()
    $Plain = $null
    try {
        $Object = Receive-CIPPCloudBackupObjectStream -Destination $Destination -Key $Key -OutStream $Stored
        if (-not $Object) { return $null }
        $Bytes = $Stored.GetBuffer()
        $Magic = if ($Stored.Length -ge 8) { [System.Text.Encoding]::ASCII.GetString($Bytes, 0, 8) } else { '' }
        $Stored.Position = 0
        if ($Magic -eq 'CIPPENC2') {
            $Plain = [System.IO.MemoryStream]::new()
            $null = Unprotect-CIPPCloudBackupStream -InputStream $Stored -OutputStream $Plain
            $Plain.Position = 0
        } elseif ($Magic -eq 'CIPPENC1') {
            $Plain = [System.IO.MemoryStream]::new((Unprotect-CIPPCloudBackupData -Bytes $Stored.ToArray()), $false)
        } else {
            $Plain = $Stored
            $Stored = $null
        }

        $Gzip = [System.IO.Compression.GZipStream]::new($Plain, [System.IO.Compression.CompressionMode]::Decompress)
        $Reader = [System.IO.StreamReader]::new($Gzip, [System.Text.Encoding]::UTF8)
        try {
            $Rows = [System.Collections.Generic.List[object]]::new()
            while ($null -ne ($Line = $Reader.ReadLine())) {
                if ($Line.Length -gt 0) { $Rows.Add([CIPP.CippJson]::ConvertFromJson($Line)) }
            }
            , $Rows.ToArray()
        } finally {
            $Reader.Dispose()
        }
    } finally {
        if ($Stored) { $Stored.Dispose() }
        if ($Plain) { $Plain.Dispose() }
    }
}
