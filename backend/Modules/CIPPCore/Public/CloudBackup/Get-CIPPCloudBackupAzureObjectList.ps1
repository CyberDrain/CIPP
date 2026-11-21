function Get-CIPPCloudBackupAzureObjectList {
    <#
    .SYNOPSIS
        Lists every blob under a prefix in an Azure Blob cloud backup destination as { Key; Size; LastModified }.
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
        $Query = [ordered]@{ restype = 'container'; comp = 'list'; maxresults = 5000 }
        if ($Prefix) { $Query.prefix = $Prefix }
        if ($Marker) { $Query.marker = $Marker }
        $Response = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'GET' -Query $Query
        $Xml = [xml]([System.Text.Encoding]::UTF8.GetString($Response.Body).TrimStart([char]0xFEFF))
        foreach ($Blob in $Xml.SelectNodes('/EnumerationResults/Blobs/Blob')) {
            [pscustomobject]@{
                Key          = $Blob.SelectSingleNode('Name').InnerText
                Size         = [int64]$Blob.SelectSingleNode('Properties/Content-Length').InnerText
                LastModified = [datetime]::Parse($Blob.SelectSingleNode('Properties/Last-Modified').InnerText, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            }
        }
        $Marker = $Xml.SelectSingleNode('/EnumerationResults/NextMarker').InnerText
    } while ($Marker)
}
