function Remove-CIPPCloudBackupObject {
    <#
    .SYNOPSIS
        Deletes an object, or with -VersionId one version of it, from a cloud backup destination. A missing object is not an error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$VersionId
    )

    if (-not $PSCmdlet.ShouldProcess($Key, 'Delete')) { return }

    $null = $PSBoundParameters.Remove('WhatIf')
    $null = $PSBoundParameters.Remove('Confirm')
    switch ($Destination.Provider) {
        'AzureBlob' { Remove-CIPPCloudBackupAzureObject @PSBoundParameters }
        'S3' { Remove-CIPPCloudBackupS3Object @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
