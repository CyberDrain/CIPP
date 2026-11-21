function Invoke-CIPPCloudBackupSharePointRestoreStep {
    <#
    .SYNOPSIS
        Restores (or previews) the next batch of files backed up from a SharePoint site's document libraries.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        $State
    )

    Invoke-CIPPCloudBackupDriveRestoreStep -Context $Context -State $State
}
