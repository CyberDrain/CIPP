function Get-CIPPCloudBackupS3ObjectList {
    <#
    .SYNOPSIS
        Lists every object under a prefix in an S3 cloud backup destination as { Key; Size; LastModified }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prefix
    )

    $Token = $null
    do {
        $Query = @{ 'list-type' = '2'; 'prefix' = $Prefix }
        if ($Token) { $Query['continuation-token'] = $Token }
        $Result = (Invoke-CIPPS3Request -Destination $Destination -Method GET -Query $Query).Xml.ListBucketResult
        foreach ($Item in $Result.Contents) {
            [pscustomobject]@{
                Key          = $Item.Key
                Size         = [int64]$Item.Size
                LastModified = [datetime]::Parse($Item.LastModified, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal')
            }
        }
        $Token = if ($Result.IsTruncated -eq 'true') { $Result.NextContinuationToken } else { $null }
    } while ($Token)
}
