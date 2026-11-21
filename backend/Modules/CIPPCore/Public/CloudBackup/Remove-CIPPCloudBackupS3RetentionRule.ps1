function Remove-CIPPCloudBackupS3RetentionRule {
    <#
    .SYNOPSIS
        Removes one lifecycle rule from an S3 cloud backup destination, keeping every other rule.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$RuleName
    )

    if ($PSCmdlet.ShouldProcess($RuleName, 'Remove S3 lifecycle rule')) {
        Update-CIPPS3LifecycleRule -Destination $Destination -RuleName $RuleName -Confirm:$false
    }
}
