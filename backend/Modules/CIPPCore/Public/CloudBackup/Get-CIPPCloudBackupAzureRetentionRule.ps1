function Get-CIPPCloudBackupAzureRetentionRule {
    <#
    .SYNOPSIS
        Returns a lifecycle management rule on an Azure Blob cloud backup destination as { Prefix; Days; Mode }, or $null when it does not exist.
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

    $Policy = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'GET' -Path 'managementPolicies/default' -AllowNotFound
    foreach ($Rule in @($Policy.properties.policy.rules)) {
        if ($null -eq $Rule -or $Rule.name -ne $RuleName) { continue }
        # Azure prefixes start with the container name; callers work with prefixes inside the container.
        $Prefix = [string]@($Rule.definition.filters.prefixMatch)[0]
        $ContainerPrefix = "$($Destination.Container)/"
        if ($Prefix.StartsWith($ContainerPrefix)) { $Prefix = $Prefix.Substring($ContainerPrefix.Length) }
        $BaseDelete = $Rule.definition.actions.baseBlob.delete
        $SnapshotDelete = $Rule.definition.actions.snapshot.delete
        $Versioned = -not $BaseDelete -and $SnapshotDelete
        return [pscustomobject]@{
            Prefix = $Prefix
            Days   = if ($Versioned) { [int]$SnapshotDelete.daysAfterCreationGreaterThan } else { [int]$BaseDelete.daysAfterModificationGreaterThan }
            Mode   = if ($Versioned) { 'Versioned' } else { 'Expire' }
        }
    }
    return $null
}
