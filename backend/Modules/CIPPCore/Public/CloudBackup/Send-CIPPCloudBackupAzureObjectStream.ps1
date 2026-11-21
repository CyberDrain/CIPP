function Send-CIPPCloudBackupAzureObjectStream {
    <#
    .SYNOPSIS
        Uploads a stream reader to an Azure Blob cloud backup destination as 8 MiB blocks and returns { Key; Bytes; VersionId }.
    .DESCRIPTION
        Called by Send-CIPPCloudBackupObjectStream with the first block already read. Uncommitted blocks of a failed
        upload are discarded by Azure after a week.
    .FUNCTIONALITY
        Internal
    .LINK
        https://learn.microsoft.com/rest/api/storageservices/put-block-list
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [hashtable]$Reader,

        [Parameter(Mandatory = $true)]
        [byte[]]$FirstBlock,

        [string]$ContentType = 'application/octet-stream',

        [hashtable]$Metadata
    )

    $Headers = @{ 'x-ms-blob-content-type' = $ContentType }
    if ($Metadata) {
        foreach ($Name in $Metadata.Keys) {
            if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                throw [System.ArgumentException]::new("'$Name' is not a valid metadata name.")
            }
            $Headers["x-ms-meta-$Name"] = [string]$Metadata[$Name]
        }
    }

    # Block ids must all have the same length; the upload id keeps them apart from other uploads to the same blob.
    $IdBytes = [byte[]]::new(20)
    [System.Array]::Copy([guid]::NewGuid().ToByteArray(), 0, $IdBytes, 0, 16)
    $BlockIds = [System.Collections.Generic.List[string]]::new()
    $Bytes = [int64]0
    $Block = $FirstBlock
    while ($Block.Length -gt 0) {
        if ($BlockIds.Count -ge 50000) {
            throw [System.ArgumentException]::new("'$Key' is larger than an Azure block blob can hold with 8 MiB blocks.")
        }
        $Number = $BlockIds.Count
        $IdBytes[16] = [byte](($Number -shr 24) -band 0xFF)
        $IdBytes[17] = [byte](($Number -shr 16) -band 0xFF)
        $IdBytes[18] = [byte](($Number -shr 8) -band 0xFF)
        $IdBytes[19] = [byte]($Number -band 0xFF)
        $BlockId = [System.Convert]::ToBase64String($IdBytes)
        $null = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'PUT' -Key $Key -Query ([ordered]@{ comp = 'block'; blockid = $BlockId }) -Body $Block
        $BlockIds.Add($BlockId)
        $Bytes += $Block.Length
        if ($Block.Length -lt 8MB) { break }
        $Block = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 8MB
    }

    $List = [System.Text.StringBuilder]::new('<?xml version="1.0" encoding="utf-8"?><BlockList>')
    foreach ($BlockId in $BlockIds) { $null = $List.Append('<Latest>').Append($BlockId).Append('</Latest>') }
    $null = $List.Append('</BlockList>')
    $Response = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'PUT' -Key $Key -Query ([ordered]@{ comp = 'blocklist' }) -Body ([System.Text.Encoding]::UTF8.GetBytes($List.ToString())) -ContentType 'application/xml' -Headers $Headers

    [pscustomobject]@{
        Key       = $Key
        Bytes     = $Bytes
        VersionId = @($Response.Headers['x-ms-version-id'])[0]
    }
}
