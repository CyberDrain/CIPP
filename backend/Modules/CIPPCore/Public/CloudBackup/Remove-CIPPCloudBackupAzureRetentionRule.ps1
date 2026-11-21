function Remove-CIPPCloudBackupAzureRetentionRule {
    <#
    .SYNOPSIS
        Removes one lifecycle management rule from an Azure Blob cloud backup destination, keeping every other rule.
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

    $Policy = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'GET' -Path 'managementPolicies/default' -AllowNotFound
    $Rules = [System.Collections.Generic.List[object]]::new()
    $Found = $false
    foreach ($Rule in @($Policy.properties.policy.rules)) {
        if ($null -eq $Rule) { continue }
        if ($Rule.name -eq $RuleName) { $Found = $true } else { $Rules.Add($Rule) }
    }
    if (-not $Found) { return }

    # A management policy must hold at least one rule, so removing the last one deletes the policy.
    if ($Rules.Count -eq 0) {
        $null = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'DELETE' -Path 'managementPolicies/default'
        return
    }
    $null = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'PUT' -Path 'managementPolicies/default' -Body @{ properties = @{ policy = @{ rules = $Rules.ToArray() } } }
}
