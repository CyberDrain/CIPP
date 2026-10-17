function New-CIPPOneDriveSkippedSiteRow {
    param($SiteSeed, $CollectionError)
    [PSCustomObject]@{
        id                          = $SiteSeed.id
        siteId                      = $SiteSeed.id
        siteUrl                     = $SiteSeed.webUrl
        siteDisplayName             = $SiteSeed.displayName
        ownerPrincipalName          = $null
        ownerObjectId               = $null
        ownerDisplayName            = $null
        driveId                     = $null
        driveWebUrl                 = $null
        libraryId                   = $null
        libraryHasUniquePermissions = $false
        collectionStatus            = 'Skipped'
        collectionError             = $CollectionError
        hasNonStandardAccess        = $null
        permissionsJson             = '[]'
        grantCount                  = 0
        collectedAt                 = (Get-Date).ToUniversalTime().ToString('o')
    }
}
