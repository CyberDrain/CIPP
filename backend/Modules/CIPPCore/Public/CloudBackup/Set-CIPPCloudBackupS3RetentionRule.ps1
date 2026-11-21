function Set-CIPPCloudBackupS3RetentionRule {
    <#
    .SYNOPSIS
        Creates or replaces the lifecycle rule for objects under a prefix on an S3 cloud backup destination.
    .DESCRIPTION
        Mode Expire expires objects after Days. Mode Versioned expires noncurrent versions Days after they became
        noncurrent, removes expired delete markers and aborts multipart uploads left incomplete for 7 days.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$RuleName,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][int]$Days,
        [ValidateSet('Expire', 'Versioned')][string]$Mode = 'Expire'
    )

    if ($RuleName.Length -gt 255) { throw [System.ArgumentException]::new('The lifecycle rule name can be at most 255 characters') }
    if ($Days -lt 1) { throw [System.ArgumentException]::new('Retention days must be at least 1') }
    if ($PSCmdlet.ShouldProcess($RuleName, 'Set S3 lifecycle rule')) {
        Update-CIPPS3LifecycleRule -Destination $Destination -RuleName $RuleName -Prefix $Prefix -Days $Days -Mode $Mode -Confirm:$false
    }
}
