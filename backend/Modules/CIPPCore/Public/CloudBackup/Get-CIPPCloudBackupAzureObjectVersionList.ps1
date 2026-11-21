function Get-CIPPCloudBackupAzureObjectVersionList {
    <#
    .SYNOPSIS
        Lists every blob version under a prefix in an Azure Blob cloud backup destination as { Key; VersionId; IsLatest; IsDeleteMarker; LastModified; Size }.
    .DESCRIPTION
        A version carrying the cippdeletedat metadata that Remove-CIPPCloudBackupAzureObject writes is reported as a delete marker.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Prefix
    )

    $Marker = $null
    do {
        $Query = [ordered]@{ restype = 'container'; comp = 'list'; include = 'versions,metadata'; maxresults = 5000 }
        if ($Prefix) { $Query.prefix = $Prefix }
        if ($Marker) { $Query.marker = $Marker }
        $Response = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'GET' -Query $Query
        $Xml = [xml]([System.Text.Encoding]::UTF8.GetString($Response.Body).TrimStart([char]0xFEFF))
        foreach ($Blob in $Xml.SelectNodes('/EnumerationResults/Blobs/Blob')) {
            $VersionNode = $Blob.SelectSingleNode('VersionId')
            $CurrentNode = $Blob.SelectSingleNode('IsCurrentVersion')
            [pscustomobject]@{
                Key            = $Blob.SelectSingleNode('Name').InnerText
                VersionId      = if ($VersionNode) { $VersionNode.InnerText } else { $null }
                IsLatest       = ($CurrentNode -and $CurrentNode.InnerText -eq 'true') -or -not $VersionNode
                IsDeleteMarker = $null -ne $Blob.SelectSingleNode('Metadata/cippdeletedat')
                LastModified   = [datetime]::Parse($Blob.SelectSingleNode('Properties/Last-Modified').InnerText, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                Size           = [int64]$Blob.SelectSingleNode('Properties/Content-Length').InnerText
            }
        }
        $Marker = $Xml.SelectSingleNode('/EnumerationResults/NextMarker').InnerText
    } while ($Marker)
}
