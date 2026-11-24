function Invoke-ExecRemoveSPOExternalUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Fully removes an external user's guest access: deletes their Entra guest account (when
        one exists) AND removes them from every SharePoint site they hold membership on, in one
        pass - so no orphaned accounts or lingering site access are left behind. Only accounts
        with userType Guest are deleted; an external account set up as a Member (cross-tenant
        sync, converted guest) keeps its Entra account and only loses site access. The inert
        SharePoint external-store entry cannot be deleted (Microsoft deprecated
        RemoveExternalUsers) and ages out on its own; sharing links the user received are
        revoked separately via the Sharing Report.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $EntraUserId = $Request.Body.EntraUserId
    $LoginName = $Request.Body.LoginName
    $SiteUrls = @($Request.Body.SiteUrls) | Where-Object { $_ }
    $DisplayName = $Request.Body.DisplayName ?? $EntraUserId ?? $LoginName

    if (-not $EntraUserId -and $SiteUrls.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ 'Results' = 'This entry has no Entra guest account and no known site memberships. The remaining SharePoint store entry cannot be removed (Microsoft deprecated the API) and ages out on its own; revoke any sharing links they hold via the Sharing Report.' } })
    }

    try {
        $Messages = [System.Collections.Generic.List[string]]::new()
        $Errors = [System.Collections.Generic.List[string]]::new()

        $EntraUser = $null
        if ($EntraUserId) {
            try {
                $EntraUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($EntraUserId)?`$select=userPrincipalName,userType" -tenantid $TenantFilter -AsApp $true
            } catch {
                $Errors.Add("Could not read the Entra account, so it was not deleted: $($_.Exception.Message)")
            }
        }

        # 1. Strip the SharePoint footprint first (needs the login; falls back to the Entra UPN).
        if ($SiteUrls.Count -gt 0) {
            $RemovalLogin = $LoginName ?? $EntraUser.userPrincipalName
            if ($RemovalLogin) {
                $Removal = Remove-CIPPSPOSiteUser -TenantFilter $TenantFilter -SiteUrls $SiteUrls -LoginName $RemovalLogin
                if ($Removal.Succeeded.Count -gt 0) {
                    $Messages.Add("Removed from $($Removal.Succeeded.Count) site(s): $($Removal.Succeeded -join ', ').")
                }
                if ($Removal.Failed.Count -gt 0) {
                    $Errors.Add("Site removal failed on: $($Removal.Failed -join '; ')")
                }
            }
        }

        # 2. Delete the Entra guest account so the user cannot sign in anywhere. A Member-type external
        # account is a deliberate setup (cross-tenant sync, converted guest) and is left alone.
        $IsMember = $EntraUser -and $EntraUser.userType -ne 'Guest'
        if ($IsMember) {
            $Messages.Add('Not deleted in Entra: this is a member account (cross-tenant sync or a converted guest); manage it in Entra ID if it should go.')
        } elseif ($EntraUser) {
            try {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$EntraUserId" -tenantid $TenantFilter -type DELETE -body '' -asapp $true
                $Messages.Add('Deleted the Entra guest account, blocking their sign-in.')
            } catch {
                $Errors.Add("Deleting the Entra guest account failed: $($_.Exception.Message)")
            }
        }

        if ($Messages.Count -eq 0) {
            throw ($Errors -join ' ')
        }
        if ($EntraUser -and -not $IsMember) {
            $Results = "Removed guest access for $($DisplayName): $($Messages -join ' ')"
        } elseif ($EntraUserId) {
            $Results = "Removed site access for $($DisplayName): $($Messages -join ' ')"
        } else {
            # No Entra account was matched, so nothing was deleted there: say so rather than claim a full removal.
            $Results = "Removed site access for $($DisplayName): $($Messages -join ' ') No Entra account is linked to this entry, so none was deleted; if one exists, delete it in Entra ID."
        }
        if ($Errors.Count -gt 0) {
            $Results += " Issues: $($Errors -join '; ')"
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = Get-CippBulkStatusCode -Total ($Messages.Count + $Errors.Count) -Failed $Errors.Count
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to remove guest access for $($DisplayName): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
