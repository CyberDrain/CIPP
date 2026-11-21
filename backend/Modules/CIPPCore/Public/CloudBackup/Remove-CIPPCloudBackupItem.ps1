function Remove-CIPPCloudBackupItem {
    <#
    .SYNOPSIS
        Marks an item deleted under the owner's prefix of a cloud backup run; on a versioned destination earlier versions are kept.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$ItemKey
    )

    $Key = "$($Context.OwnerPrefix)$($ItemKey.TrimStart('/'))"
    if ($PSCmdlet.ShouldProcess($Key, 'Delete')) {
        Remove-CIPPCloudBackupObject -Destination $Context.Destination -Key $Key
    }
}
