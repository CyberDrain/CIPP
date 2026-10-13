function Invoke-ListSiteRecycleBin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.SiteRecycleBin.Read
    .DESCRIPTION
        Lists the contents of a SharePoint site's recycle bin (first and second stage) via the
        SharePoint REST API with certificate authentication.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl

    $ItemTypeNames = @{ 1 = 'File'; 2 = 'File Version'; 3 = 'List Item'; 4 = 'List'; 5 = 'Folder'; 6 = 'Folder'; 7 = 'Attachment'; 8 = 'List Item Version'; 10 = 'Web' }
    $ItemStateNames = @{ 1 = 'First Stage'; 2 = 'Second Stage' }

    if (-not $SiteUrl) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ 'Results' = 'SiteUrl is required.' } })
    }

    try {
        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Scope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri

        $AllItems = [System.Collections.Generic.List[object]]::new()
        $Skip = 0
        $PageSize = 500
        $Guard = 0
        
        while ($Guard -lt 100) {
            $Guard++
            $Uri = "$BaseUri/site/RecycleBin?`$top=$PageSize&`$skip=$Skip&`$orderby=DeletedDate desc"
            $Page = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
            $Items = @()
            if ($null -ne $Page.value) {
                $Items = @($Page.value)
            } elseif ($Page -is [System.Array]) {
                $Items = @($Page)
            } elseif ($Page.PSObject.Properties.Name -contains 'Id') {
                $Items = @($Page)
            }
            
            if ($Items.Count -eq 0) { break }
            
            foreach ($Item in $Items) {
                $AllItems.Add($Item)
            }
            
            $Skip += $PageSize
            if ($Items.Count -lt $PageSize) { break }
        }

        $Body = @($AllItems | ForEach-Object {
                [PSCustomObject]@{
                    Id            = $_.Id
                    Title         = $_.Title
                    LeafName      = $_.LeafName
                    DirName       = $_.DirName
                    ItemType      = $ItemTypeNames[[int]$_.ItemType] ?? $_.ItemType
                    ItemState     = $ItemStateNames[[int]$_.ItemState] ?? $_.ItemState
                    Size          = $_.Size
                    DeletedByName = $_.DeletedByName
                    DeletedDate   = $_.DeletedDate
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list the recycle bin for $($SiteUrl): $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}
