function Invoke-CIPPCloudBackupOneDriveStep {
    <#
    .SYNOPSIS
        Backs up one page of changes from a user's OneDrive.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        $State
    )

    $Drives = $null
    if (-not $State -or $State.RunId -ne $Context.RunId) {
        try {
            $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Context.OwnerId)/drive?`$select=id,name,webUrl" -tenantid $Context.TenantFilter -asapp $true
        } catch {
            if ($_.Exception.Message -notmatch 'itemNotFound|ResourceNotFound|404') { throw }
            return [pscustomobject]@{
                State        = $State
                Done         = $true
                Items        = 0
                Bytes        = [int64]0
                Deleted      = 0
                Warnings     = @("No OneDrive was found for this user: $($_.Exception.Message)")
                IndexEntries = @()
            }
        }
        $Drives = @(@{ Id = $Drive.id; Name = 'OneDrive'; WebUrl = $Drive.webUrl })
    }
    Invoke-CIPPCloudBackupDriveStep -Context $Context -State $State -Drives $Drives
}
