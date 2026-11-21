function Get-CIPPCloudBackupSharePointOwner {
    <#
    .SYNOPSIS
        Lists every SharePoint site in a tenant except personal (OneDrive) sites.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # isPersonalSite eq false returns an empty set against getAllSites, so personal sites are dropped here.
    $Sites = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=id,displayName,name,webUrl,isPersonalSite&`$top=999" -tenantid $TenantFilter -asapp $true
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Site in $Sites) {
        if (-not $Site.id -or $Site.isPersonalSite -or -not $Seen.Add([string]$Site.id)) { continue }
        [pscustomobject]@{
            OwnerId           = [string]$Site.id
            OwnerType         = 'Site'
            DisplayName       = $Site.displayName ?? $Site.name
            UserId            = $null
            UserPrincipalName = $null
            SiteUrl           = $Site.webUrl
        }
    }
}
