function Set-CIPPCloudBackupAzureRetentionRule {
    <#
    .SYNOPSIS
        Creates or replaces a lifecycle management rule for blobs under a prefix, keeping every other rule.
    .DESCRIPTION
        Mode Expire deletes blobs a number of days after they were last modified. Mode Versioned writes a snapshot-only
        rule that records the days and deletes nothing CIPP writes: Azure ages a previous version from its first write,
        not from when it was replaced, so Remove-CIPPCloudBackupExpiredVersion prunes versions instead.
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

    if ($RuleName -notmatch '^[A-Za-z0-9-]{1,256}$') {
        throw [System.ArgumentException]::new("'$RuleName' is not a valid lifecycle rule name.")
    }
    if (-not $PSCmdlet.ShouldProcess($RuleName, 'Set lifecycle rule')) { return }

    $Policy = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'GET' -Path 'managementPolicies/default' -AllowNotFound
    $Rules = [System.Collections.Generic.List[object]]::new()
    foreach ($Rule in @($Policy.properties.policy.rules)) {
        if ($null -ne $Rule -and $Rule.name -ne $RuleName) { $Rules.Add($Rule) }
    }
    $Actions = if ($Mode -eq 'Versioned') {
        [ordered]@{ snapshot = [ordered]@{ delete = [ordered]@{ daysAfterCreationGreaterThan = $Days } } }
    } else {
        [ordered]@{ baseBlob = [ordered]@{ delete = [ordered]@{ daysAfterModificationGreaterThan = $Days } } }
    }
    $Rules.Add([ordered]@{
            enabled    = $true
            name       = $RuleName
            type       = 'Lifecycle'
            definition = [ordered]@{
                actions = $Actions
                filters = [ordered]@{
                    blobTypes   = @('blockBlob')
                    prefixMatch = @("$($Destination.Container)/$Prefix")
                }
            }
        })

    $null = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'PUT' -Path 'managementPolicies/default' -Body @{ properties = @{ policy = @{ rules = $Rules.ToArray() } } }
}
