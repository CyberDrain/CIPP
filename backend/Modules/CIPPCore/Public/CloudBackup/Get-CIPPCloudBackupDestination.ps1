function Get-CIPPCloudBackupDestination {
    <#
    .SYNOPSIS
        Returns cloud backup destinations from the Config table, with the stored secret when -IncludeSecret is set.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [switch]$IncludeSecret
    )

    $Filter = "PartitionKey eq 'CloudBackupDestination'"
    if ($Id) {
        $ParsedId = [guid]::Empty
        if (-not [guid]::TryParse($Id, [ref]$ParsedId)) {
            throw [System.ArgumentException]::new("'$Id' is not a valid destination id.")
        }
        $Filter = "$Filter and RowKey eq '$ParsedId'"
    }

    $Table = Get-CIPPTable -tablename 'Config'
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    foreach ($Row in $Rows) {
        $LastTest = $null
        if ($Row.LastTest) {
            try { $LastTest = [CIPP.CippJson]::ConvertFromJson([string]$Row.LastTest) } catch { $LastTest = $null }
        }
        $Destination = [pscustomobject]@{
            Id             = $Row.RowKey
            Name           = $Row.Name
            Provider       = $Row.Provider
            StorageAccount = $Row.StorageAccount
            Container      = $Row.Container
            SubscriptionId = $Row.SubscriptionId
            ResourceGroup  = $Row.ResourceGroup
            AzureTenantId  = $Row.AzureTenantId
            ClientId       = $Row.ClientId
            Endpoint       = $Row.Endpoint
            Region         = $Row.Region
            Bucket         = $Row.Bucket
            AccessKeyId    = $Row.AccessKeyId
            ForcePathStyle = $Row.ForcePathStyle -eq $true
            AuthMode       = if ($Row.AuthMode -eq 'CippApp') { 'CippApp' } elseif ($Row.Provider -eq 'AzureBlob') { 'ServicePrincipal' } else { $null }
            ProvisionedBy  = if ($Row.ProvisionedBy) { "$($Row.ProvisionedBy)" } else { $null }
            ImmutabilityDays = if (($Row.ImmutabilityDays -as [int]) -gt 0) { [int]$Row.ImmutabilityDays } else { $null }
            LastTest       = $LastTest
            LastTestedAt   = $Row.LastTestedAt
        }
        if ($IncludeSecret -and $Destination.AuthMode -ne 'CippApp') {
            $Destination.PSObject.Properties.Add([psnoteproperty]::new('Secret', (Get-CIPPSecret -Name "CloudBackupDest-$($Row.RowKey)")))
        }
        $Destination
    }
}
