function Set-CIPPCloudBackupObject {
    <#
    .SYNOPSIS
        Uploads an object to a cloud backup destination.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Body,

        [string]$ContentType = 'application/octet-stream',

        [hashtable]$Metadata
    )

    if (-not $PSCmdlet.ShouldProcess($Key, 'Upload')) { return }

    $null = $PSBoundParameters.Remove('WhatIf')
    $null = $PSBoundParameters.Remove('Confirm')
    switch ($Destination.Provider) {
        'AzureBlob' { Set-CIPPCloudBackupAzureObject @PSBoundParameters }
        'S3' { Set-CIPPCloudBackupS3Object @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
