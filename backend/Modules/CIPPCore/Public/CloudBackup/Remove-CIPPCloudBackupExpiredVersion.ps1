function Remove-CIPPCloudBackupExpiredVersion {
    <#
    .SYNOPSIS
        Deletes previous versions under a prefix that were replaced or deleted more than -Days ago, and returns { Examined; Deleted; Failed; Skipped; Errors }.
    .DESCRIPTION
        Only Azure needs this; on S3 the Versioned lifecycle rule does the same and nothing is called. -MaxDeletes caps
        one call's deletes; the next call continues. Current versions are never deleted.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$Days,

        [ValidateRange(1, 1000000)]
        [int]$MaxDeletes = 1000
    )

    if (-not $PSCmdlet.ShouldProcess($Prefix, 'Delete expired versions')) { return }

    $null = $PSBoundParameters.Remove('WhatIf')
    $null = $PSBoundParameters.Remove('Confirm')
    switch ($Destination.Provider) {
        'AzureBlob' { Remove-CIPPCloudBackupAzureExpiredVersion @PSBoundParameters -Confirm:$false }
        'S3' { [pscustomobject]@{ Examined = 0; Deleted = 0; Failed = 0; Skipped = 0; Errors = @() } }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
