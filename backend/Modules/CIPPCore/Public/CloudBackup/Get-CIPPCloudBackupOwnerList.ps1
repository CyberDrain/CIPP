function Get-CIPPCloudBackupOwnerList {
    <#
    .SYNOPSIS
        Lists the owners (mailboxes, OneDrives, sites, teams, chat users) a cloud backup workload covers in a tenant, minus the policy's exclusions.
    .DESCRIPTION
        Excludes users by id or UPN, members of excluded groups (transitively) and the excluded groups themselves, and
        sites by URL.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('exchange', 'onedrive', 'sharepoint', 'teams')]
        [string]$Workload,

        $Exclusions
    )

    $Names = @{ exchange = 'Exchange'; onedrive = 'OneDrive'; sharepoint = 'SharePoint'; teams = 'Teams' }
    $Owners = @(& "Get-CIPPCloudBackup$($Names[$Workload.ToLowerInvariant()])Owner" -TenantFilter $TenantFilter)

    $ExcludedUsers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($User in @($Exclusions.Users)) { if ($User) { [void]$ExcludedUsers.Add("$User") } }
    $ExcludedSites = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Site in @($Exclusions.Sites)) { if ($Site) { [void]$ExcludedSites.Add("$Site".TrimEnd('/')) } }
    $ExcludedGroups = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Group in @($Exclusions.Groups)) { if ($Group) { [void]$ExcludedGroups.Add("$Group") } }

    if ($ExcludedGroups.Count -gt 0) {
        $Requests = foreach ($GroupId in $ExcludedGroups) {
            @{ id = $GroupId; method = 'GET'; url = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=id,userPrincipalName&`$top=999" }
        }
        foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true)) {
            if ($Response.status -eq 404) { continue }
            if ($Response.status -lt 200 -or $Response.status -ge 300) {
                throw "Could not read the members of excluded group $($Response.id): $($Response.body.error.message)"
            }
            foreach ($Member in @($Response.body.value)) {
                if ($Member.id) { [void]$ExcludedUsers.Add("$($Member.id)") }
                if ($Member.userPrincipalName) { [void]$ExcludedUsers.Add("$($Member.userPrincipalName)") }
            }
        }
    }

    foreach ($Owner in $Owners) {
        if ($null -eq $Owner) { continue }
        if ($ExcludedGroups.Contains("$($Owner.OwnerId)")) { continue }
        if ($ExcludedUsers.Count -gt 0 -and ($ExcludedUsers.Contains("$($Owner.OwnerId)") -or ($Owner.UserId -and $ExcludedUsers.Contains("$($Owner.UserId)")) -or ($Owner.UserPrincipalName -and $ExcludedUsers.Contains("$($Owner.UserPrincipalName)")))) { continue }
        if ($Owner.SiteUrl -and $ExcludedSites.Contains("$($Owner.SiteUrl)".TrimEnd('/'))) { continue }
        $Owner
    }
}
