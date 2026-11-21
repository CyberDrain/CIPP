function Send-CIPPCloudBackupS3ObjectStream {
    <#
    .SYNOPSIS
        Uploads a stream reader to an S3 cloud backup destination as a multipart upload and returns { Key; Bytes; VersionId }.
    .DESCRIPTION
        Called by Send-CIPPCloudBackupObjectStream with the first 8 MiB part already read. Parts grow by 8 MiB every
        1,000 parts so the 10,000-part limit allows objects of about 440 GB. A failed upload is aborted.
    .FUNCTIONALITY
        Internal
    .LINK
        https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][hashtable]$Reader,
        [Parameter(Mandatory)][byte[]]$FirstBlock,
        [string]$ContentType = 'application/octet-stream',
        [hashtable]$Metadata
    )

    $Headers = @{ 'Content-Type' = $ContentType }
    if ($Metadata) {
        foreach ($Name in $Metadata.Keys) {
            $Value = [string]$Metadata[$Name]
            if ($Name -notmatch '^[A-Za-z0-9_-]+$' -or $Value -notmatch '^[\x20-\x7E]*$') {
                throw [System.ArgumentException]::new("Metadata '$Name' needs a name of letters, digits, '-' or '_' and a printable ASCII value")
            }
            $Headers["x-amz-meta-$Name"] = $Value
        }
    }

    # Without a body the client drops Content-Type, which is signed.
    $Create = Invoke-CIPPS3Request -Destination $Destination -Method POST -Key $Key -Query @{ uploads = '' } -Body ([byte[]]::new(0)) -Headers $Headers
    $CreateXml = [xml]::new()
    $CreateXml.Load([System.IO.MemoryStream]::new($Create.Body))
    $UploadId = $CreateXml.DocumentElement['UploadId'].InnerText
    if (-not $UploadId) { throw "S3 did not return an upload id for object '$Key'" }

    try {
        $ETags = [System.Collections.Generic.List[string]]::new()
        $Bytes = [int64]0
        $Block = $FirstBlock
        $PartSize = 8MB
        while ($Block.Length -gt 0) {
            $PartNumber = $ETags.Count + 1
            if ($PartNumber -gt 10000) { throw [System.ArgumentException]::new("'$Key' is larger than an S3 multipart upload can hold.") }
            $Part = Invoke-CIPPS3Request -Destination $Destination -Method PUT -Key $Key -Query @{ partNumber = [string]$PartNumber; uploadId = $UploadId } -Body $Block
            $ETags.Add([string]$Part.Headers['ETag'])
            $Bytes += $Block.Length
            if ($Block.Length -lt $PartSize) { break }
            $PartSize = 8MB * (1 + [Math]::Floor($PartNumber / 1000))
            $Block = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size $PartSize
        }

        $Complete = [System.Text.StringBuilder]::new('<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/">')
        for ($i = 0; $i -lt $ETags.Count; $i++) {
            $null = $Complete.Append('<Part><PartNumber>').Append($i + 1).Append('</PartNumber><ETag>').Append([System.Security.SecurityElement]::Escape($ETags[$i])).Append('</ETag></Part>')
        }
        $null = $Complete.Append('</CompleteMultipartUpload>')
        $Response = Invoke-CIPPS3Request -Destination $Destination -Method POST -Key $Key -Query @{ uploadId = $UploadId } -Body ([System.Text.Encoding]::UTF8.GetBytes($Complete.ToString())) -Headers @{ 'Content-Type' = 'application/xml' }

        # S3 can report a failed CompleteMultipartUpload as 200 with an Error document.
        $ResultXml = [xml]::new()
        $ResultXml.Load([System.IO.MemoryStream]::new($Response.Body))
        if ($ResultXml.DocumentElement.LocalName -eq 'Error') {
            throw "S3 could not complete the upload of object '$Key': $($ResultXml.DocumentElement['Code'].InnerText) $($ResultXml.DocumentElement['Message'].InnerText)"
        }
    } catch {
        try {
            $null = Invoke-CIPPS3Request -Destination $Destination -Method DELETE -Key $Key -Query @{ uploadId = $UploadId }
        } catch {
            Write-Information "Could not abort the S3 multipart upload of '$Key': $($_.Exception.Message)"
        }
        throw
    }

    $VersionId = $Response.Headers['x-amz-version-id']
    [pscustomobject]@{
        Key       = $Key
        Bytes     = $Bytes
        VersionId = if ($VersionId -and $VersionId -ne 'null') { $VersionId } else { $null }
    }
}
