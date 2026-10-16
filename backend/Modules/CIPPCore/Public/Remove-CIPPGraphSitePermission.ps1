function Remove-CIPPGraphSitePermission {
    <#
    .NOTES
        Permission: Graph | GET /sites/{id} | Application | Sites.Read.All | Sites.ReadWrite.All
        Permission: Graph | DELETE /sites/{id}/permissions/{id} | Application | Sites.FullControl.All
    #>
    param($TenantFilter, $SiteUrl, $SiteId, $PermissionId, $PrincipalName)

    $ResolvedSiteId = $SiteId
    if ([string]::IsNullOrWhiteSpace($ResolvedSiteId)) {
        $ParsedUrl = [System.Uri]$SiteUrl
        $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
            $ParsedUrl.Host
        } else {
            "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
        }
        $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment`?`$select=id" -tenantid $TenantFilter -asapp $true
        $ResolvedSiteId = $SiteMeta.id
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedSiteId)) { throw 'Could not resolve Graph site id.' }

    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/sites/$ResolvedSiteId/permissions/$PermissionId" -tenantid $TenantFilter -type DELETE -asapp $true
    $Label = $PrincipalName ?? $PermissionId
    return "Successfully removed Graph site permission for $Label."
}
