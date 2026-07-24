// Migration-only Bicep template for cipp (self-hosted container architecture).
// References an existing storage account and key vault — only creates the App Service Plan + Web App.
//
// NOTE: the web app name and the key vault name MUST be identical — the backend resolves
// its vault as $env:WEBSITE_SITE_NAME (see Get-CippKeyVaultName). webAppName defaults to
// the existing vault name for exactly that reason.

@description('Container image for the cipp web app.')
param containerImage string = 'DOCKER|ghcr.io/cyberdrain/cipp:latest'

@description('Location for new resources.')
param location string = resourceGroup().location

@description('Name of the existing storage account to connect the web app to.')
param existingStorageAccountName string

@description('Name of the existing Key Vault to grant the web app access to.')
param existingKeyVaultName string

@description('Name for the new web app and the basis for the plan name. Defaults to the existing Key Vault name.')
param webAppName string = existingKeyVaultName

// ── Derive plan name from web app name ────────────────────────────────────────
var serverFarmName = '${webAppName}-plan'

// ── Reference existing storage account ───────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: existingStorageAccountName
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

// ── Reference existing Key Vault ──────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: existingKeyVaultName
}

// ── App Service Plan (Linux B2) ───────────────────────────────────────────────
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
    reserved: true
    perSiteScaling: false
    maximumElasticWorkerCount: 1
    isSpot: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
}

// ── cipp Web App (Linux container) ───────────────────────────────────────────
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
          name: 'WEBSITE_RESOURCE_GROUP'
          value: resourceGroup().name
        }
      ]
    }
  }
}

// ── Grant web app Managed Identity access to existing Key Vault ───────────────
resource kvAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: webApp.identity.principalId
        permissions: {
          keys: []
          secrets: ['all']
          certificates: []
        }
      }
    ]
  }
}

// ── Role Assignment — Web App as Contributor on itself ────────────────────────
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, webApp.name, 'Contributor')
  scope: webApp
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b24988ac-6180-42a0-ab88-20f7382dd24c'
    )
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Tag resource group ────────────────────────────────────────────────────────
resource tag 'Microsoft.Resources/tags@2022-09-01' = {
  name: 'default'
  properties: {
    tags: {
      Linux: 'true'
      NG: 'true'
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output hostname string = webApp.properties.defaultHostName
output webAppName string = webApp.name
output keyVaultName string = keyVault.name
