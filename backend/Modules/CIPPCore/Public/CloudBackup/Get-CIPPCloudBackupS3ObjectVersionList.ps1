function Get-CIPPCloudBackupS3ObjectVersionList {
    <#
    .SYNOPSIS
        Lists every version and delete marker under a prefix in an S3 cloud backup destination as { Key; VersionId; IsLatest; IsDeleteMarker; LastModified; Size }.
    .FUNCTIONALITY
        Internal
    .LINK
        https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectVersions.html
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix
    )

    $KeyMarker = $null
    $VersionMarker = $null
    do {
        $Query = @{ versions = ''; prefix = $Prefix }
        if ($KeyMarker) { $Query['key-marker'] = $KeyMarker }
        if ($VersionMarker) { $Query['version-id-marker'] = $VersionMarker }
        $Result = (Invoke-CIPPS3Request -Destination $Destination -Method GET -Query $Query).Xml.DocumentElement
        foreach ($Node in $Result.ChildNodes) {
            if ($Node.LocalName -ne 'Version' -and $Node.LocalName -ne 'DeleteMarker') { continue }
            [pscustomobject]@{
                Key            = $Node['Key'].InnerText
                VersionId      = $Node['VersionId'].InnerText
                IsLatest       = $Node['IsLatest'].InnerText -eq 'true'
                IsDeleteMarker = $Node.LocalName -eq 'DeleteMarker'
                LastModified   = [datetime]::Parse($Node['LastModified'].InnerText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal')
                Size           = if ($Node['Size']) { [int64]$Node['Size'].InnerText } else { [int64]0 }
            }
        }
        $Truncated = $Result['IsTruncated'] -and $Result['IsTruncated'].InnerText -eq 'true'
        $KeyMarker = if ($Truncated -and $Result['NextKeyMarker']) { $Result['NextKeyMarker'].InnerText } else { $null }
        $VersionMarker = if ($Truncated -and $Result['NextVersionIdMarker']) { $Result['NextVersionIdMarker'].InnerText } else { $null }
    } while ($KeyMarker)
}
