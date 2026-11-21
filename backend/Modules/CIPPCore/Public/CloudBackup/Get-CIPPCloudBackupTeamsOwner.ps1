function Get-CIPPCloudBackupTeamsOwner {
    <#
    .SYNOPSIS
        Lists the Teams backup owners of a tenant: one per team (channel messages) and one per Teams-licensed user (chats).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter
    )

    $Teams = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName&`$top=999" -tenantid $TenantFilter
    foreach ($Team in $Teams) {
        [pscustomobject]@{
            OwnerId           = $Team.id
            OwnerType         = 'Team'
            DisplayName       = $Team.displayName
            UserId            = $null
            UserPrincipalName = $null
            SiteUrl           = $null
        }
    }

    New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Member'&`$select=id,displayName,userPrincipalName,assignedPlans&`$top=999" -tenantid $TenantFilter -Stream | & {
        process {
            foreach ($Plan in $_.assignedPlans) {
                if ($Plan.service -eq 'TeamspaceAPI' -and $Plan.capabilityStatus -eq 'Enabled') {
                    [pscustomobject]@{
                        OwnerId           = $_.id
                        OwnerType         = 'UserChats'
                        DisplayName       = $_.displayName
                        UserId            = $_.id
                        UserPrincipalName = $_.userPrincipalName
                        SiteUrl           = $null
                    }
                    break
                }
            }
        }
    }
}
