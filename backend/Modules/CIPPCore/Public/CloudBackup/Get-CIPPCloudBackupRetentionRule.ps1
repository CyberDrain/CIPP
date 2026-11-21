function Get-CIPPCloudBackupRetentionRule {
    <#
    .SYNOPSIS
        Returns a lifecycle rule on a cloud backup destination as { Prefix; Days; Mode } (Mode Expire or Versioned), or $null when it does not exist.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$RuleName
    )

    switch ($Destination.Provider) {
        'AzureBlob' { Get-CIPPCloudBackupAzureRetentionRule @PSBoundParameters }
        'S3' { Get-CIPPCloudBackupS3RetentionRule @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
