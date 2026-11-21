function Set-CIPPCloudBackupRetentionRule {
    <#
    .SYNOPSIS
        Creates or replaces a lifecycle rule for objects under a prefix, keeping every other rule.
    .DESCRIPTION
        Mode Expire deletes objects a number of days after they were written. Mode Versioned never expires current
        versions. On S3 the rule deletes noncurrent versions the given days after they became noncurrent and removes
        delete markers with no versions left; on Azure Remove-CIPPCloudBackupExpiredVersion does that pruning.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$RuleName,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$Days,

        [ValidateSet('Expire', 'Versioned')]
        [string]$Mode = 'Expire'
    )

    if (-not $PSCmdlet.ShouldProcess($RuleName, 'Set lifecycle rule')) { return }

    $null = $PSBoundParameters.Remove('WhatIf')
    $null = $PSBoundParameters.Remove('Confirm')
    switch ($Destination.Provider) {
        'AzureBlob' { Set-CIPPCloudBackupAzureRetentionRule @PSBoundParameters }
        'S3' { Set-CIPPCloudBackupS3RetentionRule @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
