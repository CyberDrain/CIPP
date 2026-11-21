function Invoke-CIPPCloudBackupSharePointStep {
    <#
    .SYNOPSIS
        Backs up one page of changes from one of a site's document libraries.
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
            $Libraries = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$($Context.OwnerId)/drives?`$select=id,name,webUrl" -tenantid $Context.TenantFilter -asapp $true
        } catch {
            if ($_.Exception.Message -notmatch 'Access to this site has been blocked|itemNotFound|ResourceNotFound|404') { throw }
            return [pscustomobject]@{
                State        = $State
                Done         = $true
                Items        = 0
                Bytes        = [int64]0
                Deleted      = 0
                Warnings     = @("The site's document libraries could not be read: $($_.Exception.Message)")
                IndexEntries = @()
            }
        }
        $Drives = @(foreach ($Library in $Libraries) {
                if ($Library.id) { @{ Id = $Library.id; Name = $Library.name; WebUrl = $Library.webUrl } }
            })
    }
    Invoke-CIPPCloudBackupDriveStep -Context $Context -State $State -Drives $Drives
}
