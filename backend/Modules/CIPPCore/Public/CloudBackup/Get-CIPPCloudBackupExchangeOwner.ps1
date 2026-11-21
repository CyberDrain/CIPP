function Get-CIPPCloudBackupExchangeOwner {
    <#
    .SYNOPSIS
        Lists the mailboxes Cloud Backup covers in a tenant: licensed user mailboxes and shared mailboxes.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Licensed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$filter=assignedLicenses/$count ne 0&$count=true&$select=id&$top=999' -tenantid $TenantFilter -ComplexFilter -Stream | & { process { [void]$Licensed.Add([string]$_.id) } }

    New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = @('UserMailbox', 'SharedMailbox'); ResultSize = 'Unlimited' } -Select 'ExternalDirectoryObjectId,UserPrincipalName,DisplayName,RecipientTypeDetails' -StreamPages | & {
        process {
            foreach ($Mailbox in $_.Value) {
                $UserId = [string]$Mailbox.ExternalDirectoryObjectId
                if (-not $UserId) { continue }
                if ($Mailbox.RecipientTypeDetails -eq 'UserMailbox' -and -not $Licensed.Contains($UserId)) { continue }
                [pscustomobject]@{
                    OwnerId           = $UserId
                    OwnerType         = [string]$Mailbox.RecipientTypeDetails
                    DisplayName       = $Mailbox.DisplayName
                    UserId            = $UserId
                    UserPrincipalName = $Mailbox.UserPrincipalName
                    SiteUrl           = $null
                }
            }
        }
    }
}
