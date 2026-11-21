function Invoke-CIPPCloudBackupAzureManagementRequest {
    <#
    .SYNOPSIS
        Sends an Azure Resource Manager request for the storage account of an Azure Blob cloud backup destination.
    .DESCRIPTION
        -Path is relative to the storage account resource. With -AllowNotFound a missing child resource returns $null;
        a missing subscription, resource group or storage account always throws ItemNotFoundException.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [ValidateSet('GET', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $true)]
        [ValidateSet('managementPolicies/default', 'blobServices/default')]
        [string]$Path,

        $Body,

        [switch]$AllowNotFound
    )

    $Account = [string]$Destination.StorageAccount
    $ParsedSubscription = [guid]::Empty
    if ($Account -notmatch '^[a-z0-9]{3,24}$') {
        throw [System.ArgumentException]::new("'$Account' is not a valid storage account name.")
    }
    if (-not [guid]::TryParse([string]$Destination.SubscriptionId, [ref]$ParsedSubscription)) {
        throw [System.ArgumentException]::new('The destination needs a valid subscription id to manage lifecycle rules and read versioning.')
    }
    if ([string]$Destination.ResourceGroup -notmatch '^[-\w.()]{1,90}$') {
        throw [System.ArgumentException]::new('The destination needs a valid resource group to manage lifecycle rules and read versioning.')
    }
    if ($Destination.AuthMode -eq 'CippApp') {
        $Authorization = (Get-GraphToken -tenantid $env:TenantID -scope 'https://management.azure.com/.default' -AsApp $true).Authorization
    } else {
        if (-not $Destination.AzureTenantId -or -not $Destination.ClientId -or -not $Destination.Secret) {
            throw [System.ArgumentException]::new('The destination needs a tenant id, client id and client secret.')
        }
        $Token = Get-CIPPClientCredentialToken -TenantId $Destination.AzureTenantId -ClientId $Destination.ClientId -ClientSecret $Destination.Secret -Scope 'https://management.azure.com/.default'
        $Authorization = "Bearer $Token"
    }
    $Uri = "https://management.azure.com/subscriptions/$ParsedSubscription/resourceGroups/$($Destination.ResourceGroup)/providers/Microsoft.Storage/storageAccounts/$Account/$($Path)?api-version=2023-05-01"

    $RequestParams = @{
        Uri                = $Uri
        Method             = $Method
        Headers            = @{ Authorization = $Authorization }
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $Json = [CIPP.CippJson]::ToJson($Body, 20)
        if ($null -eq $Json) { $Json = ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
        $RequestParams.Body = $Json
        $RequestParams.ContentType = 'application/json'
    }

    $Response = Invoke-CIPPRestMethod @RequestParams
    if ($null -eq $Response -or $null -eq $Response.error) { return $Response }

    $ErrorCode = [string]$Response.error.code
    $ErrorMessage = [string]$Response.error.message
    if ($ErrorCode -in @('SubscriptionNotFound', 'ResourceGroupNotFound', 'ParentResourceNotFound', 'StorageAccountNotFound')) {
        throw [System.Management.Automation.ItemNotFoundException]::new("Storage account '$Account' was not found in resource group '$($Destination.ResourceGroup)': $ErrorMessage")
    }
    if ($AllowNotFound -and $ErrorCode -match 'NotFound') { return $null }
    throw "Azure Resource Manager returned $($ErrorCode): $ErrorMessage"
}
