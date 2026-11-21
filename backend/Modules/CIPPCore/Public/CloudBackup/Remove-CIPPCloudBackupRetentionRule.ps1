function Remove-CIPPCloudBackupRetentionRule {
    <#
    .SYNOPSIS
        Removes one lifecycle rule from a cloud backup destination, keeping every other rule.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$RuleName
    )

    if (-not $PSCmdlet.ShouldProcess($RuleName, 'Remove lifecycle rule')) { return }

    $null = $PSBoundParameters.Remove('WhatIf')
    $null = $PSBoundParameters.Remove('Confirm')
    switch ($Destination.Provider) {
        'AzureBlob' { Remove-CIPPCloudBackupAzureRetentionRule @PSBoundParameters }
        'S3' { Remove-CIPPCloudBackupS3RetentionRule @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
