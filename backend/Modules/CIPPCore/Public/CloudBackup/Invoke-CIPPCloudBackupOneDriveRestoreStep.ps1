function Invoke-CIPPCloudBackupOneDriveRestoreStep {
    <#
    .SYNOPSIS
        Restores (or previews) the next batch of files backed up from a user's OneDrive.
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
