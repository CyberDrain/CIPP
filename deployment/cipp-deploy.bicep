// Full deployment template for a standalone self-hosted cipp instance.
// Creates all required resources from scratch (storage account, app service plan, web app,
// key vault) in the customer's own subscription. Unlike InternalCIPP-ng.bicep, this template
// has no dependency on CyberDrain's internal hosting/management plane — the deployed instance
// configures its own Entra app registration (application ID/secret, refresh token, tenant ID)
// through the cipp application's own setup UI, which writes those values into the key vault
// created here via the web app's managed identity.
//
// NOTE: the web app name and the key vault name MUST be identical — the backend resolves
// its vault as $env:WEBSITE_SITE_NAME (see Get-CippKeyVaultName).

@description('Name used as base-template to name the resources deployed in Azure.')
param baseName string = 'CIPP'

@description('Container image for the cipp web app.')
param containerImage string = 'DOCKER|ghcr.io/cyberdrain/cipp:latest'

@description('Location for the web app and storage account.')
param location string = resourceGroup().location

@description('AAD tenant allow-list for CIPP auth app setting. Defaults to * (all tenants).')
param aadTenantId string = '*'

@description('When true (default), placeholder Key Vault secrets are created for a fresh deployment; real credentials are then configured from within the cipp application setup UI. Set to false when redeploying this template over an existing instance so real secrets are not overwritten with placeholders.')
param updateKeyVaultSecrets bool = true

// Variables
var suffix = substring(toLower(uniqueString(resourceGroup().id, resourceGroup().location)), 0, 5)
var webAppName = toLower('${baseName}${suffix}')
var funcStorageName = toLower('${substring(baseName, 0, min(length(baseName), 16))}stg${suffix}')
var serverFarmName = '${webAppName}-plan'
var uniqueResourceNameBase = toLower('${baseName}${suffix}')
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

// Storage Account
// Hardened: HTTPS only, minimum TLS 1.2 (TLS 1.3 is negotiated automatically when the
// client supports it; a 1.3 floor would lock out older management clients), no public
// blob access, infrastructure (double) encryption — settable only at creation time.
// Shared-key auth must stay enabled: the backend consumes AzureWebJobsStorage as a
// key-based connection string (Get-CIPPTable via AzBobbyTables), so disabling it breaks
// every table/queue/blob call. Network default stays Allow because the web app has no
// VNet integration; Deny would cut the app off from its own storage.
resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: funcStorageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
    }
  }
}

// Azure Files — maximum-security SMB posture. The containerized app does not use file
// shares at all (no content share like the old function apps), so this is pure
// defense-in-depth: newest SMB dialect only, Kerberos-only auth, AES-256 everywhere.
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        versions: 'SMB3.1.1'
        authenticationMethods: 'Kerberos'
        kerberosTicketEncryption: 'AES-256'
        channelEncryption: 'AES-256-GCM'
      }
    }
  }
}

// App Service Plan (Linux)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: serverFarmName
  location: location
  sku: {
    name: 'B2'
    tier: 'Basic'
    size: 'B2'
    family: 'B'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    perSiteScaling: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true // Required for Linux plans
    isXenon: false
    hyperV: false
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
}

// cipp Web App (Linux container)
resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    reserved: true
    siteConfig: {
      linuxFxVersion: containerImage
      acrUseManagedIdentityCreds: false
      alwaysOn: true
      http20Enabled: true
      use32BitWorkerProcess: false
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
          value: aadTenantId
        }
        {
          name: 'WEBSITE_RESOURCE_GROUP'
          value: resourceGroup().name
        }
      ]
    }
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: uniqueResourceNameBase
  location: resourceGroup().location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: webApp.identity.principalId
        permissions: {
          keys: []
          secrets: [
            'all'
          ]
          certificates: []
        }
      }
    ]
    enabledForDeployment: true
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
  }
}

// Key Vault Secrets — created with placeholder values by default so a fresh instance
// has the secrets present; the cipp application replaces them via its own setup UI
// after deployment, using the web app's managed identity access to this vault.
// Pass updateKeyVaultSecrets=false when redeploying over an existing instance.
resource applicationIdSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = if (updateKeyVaultSecrets) {
  parent: keyVault
  name: 'applicationid'
  properties: {
    contentType: 'text/plain'
    value: 'LongApplicationId'
  }
}

resource applicationSecretSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = if (updateKeyVaultSecrets) {
  parent: keyVault
  name: 'applicationsecret'
  properties: {
    contentType: 'text/plain'
    value: 'AppSecret'
  }
}

resource refreshTokenSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = if (updateKeyVaultSecrets) {
  parent: keyVault
  name: 'refreshtoken'
  properties: {
    contentType: 'text/plain'
    value: 'RefreshToken'
  }
}

resource tenantIdSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = if (updateKeyVaultSecrets) {
  parent: keyVault
  name: 'tenantid'
  properties: {
    contentType: 'text/plain'
    value: 'tenantId'
  }
}

// Role Assignment - Web App as Contributor on itself
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, webApp.name, 'Contributor')
  scope: webApp
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    ) // Contributor role
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Add Linux tag to resource group
resource tag 'Microsoft.Resources/tags@2022-09-01' = {
  name: 'default'
  properties: {
    tags: {
      Linux: 'true'
    }
  }
}

// Outputs
output hostname string = webApp.properties.defaultHostName
output keyVaultName string = keyVault.name
output webAppName string = webApp.name
