function Open-CIPPCloudBackupIndexReader {
    <#
    .SYNOPSIS
        Opens a stored index part or snapshot as a text reader over its decrypted, decompressed JSON lines.
    .DESCRIPTION
        The object is staged in temporary files that are deleted when the reader is disposed, so memory use does not
        grow with the file. The caller must dispose the reader.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([System.IO.StreamReader])]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $TempDirectory = [System.IO.Path]::GetTempPath()
    $Raw = [System.IO.FileStream]::new([System.IO.Path]::Combine($TempDirectory, [System.IO.Path]::GetRandomFileName()), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 81920, [System.IO.FileOptions]::DeleteOnClose)
    $Plain = $null
    try {
        $Received = Receive-CIPPCloudBackupObjectStream -Destination $Destination -Key $Key -OutStream $Raw
        if (-not $Received) {
            throw [System.Management.Automation.ItemNotFoundException]::new("The backup index file $Key no longer exists.")
        }
        $Raw.Position = 0
        $Head = [byte[]]::new(8)
        $HeadLength = $Raw.Read($Head, 0, 8)
        $Raw.Position = 0
        $Magic = if ($HeadLength -eq 8) { [System.Text.Encoding]::ASCII.GetString($Head) } else { '' }
        if ($Magic -eq 'CIPPENC2') {
            $Plain = [System.IO.FileStream]::new([System.IO.Path]::Combine($TempDirectory, [System.IO.Path]::GetRandomFileName()), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 81920, [System.IO.FileOptions]::DeleteOnClose)
            $null = Unprotect-CIPPCloudBackupStream -InputStream $Raw -OutputStream $Plain
            $Raw.Dispose()
            $Plain.Position = 0
        } elseif ($Magic -eq 'CIPPENC1') {
            $Bytes = [byte[]]::new($Raw.Length)
            $Read = 0
            while ($Read -lt $Bytes.Length) {
                $Count = $Raw.Read($Bytes, $Read, $Bytes.Length - $Read)
                if ($Count -le 0) { break }
                $Read += $Count
            }
            $Raw.Dispose()
            $Plain = [System.IO.MemoryStream]::new((Unprotect-CIPPCloudBackupData -Bytes $Bytes), $false)
        } else {
            $Plain = $Raw
        }
        $Gzip = [System.IO.Compression.GZipStream]::new($Plain, [System.IO.Compression.CompressionMode]::Decompress)
        return [System.IO.StreamReader]::new($Gzip, [System.Text.UTF8Encoding]::new($false))
    } catch {
        if ($Plain) { $Plain.Dispose() }
        $Raw.Dispose()
        throw
    }
}
