#requires -Version 7.0
<#
.SYNOPSIS
    Migrates a self-hosted CIPP instance to the containerized architecture (Linux container web app).

.DESCRIPTION
    Deploys the cipp-migration.json ARM template, preserves the existing CIPP SAM credentials
    and API client auth settings from the current function app, migrates SWA role assignments
    to the allowedUsers storage table, then removes the Static Web App entirely.
    Existing function apps, app service plans, Application Insights components, and their
    smart detector alert rules are also removed as part of the cutover.

.PARAMETER ResourceGroupName
    The resource group containing the CIPP instance to migrate.

.PARAMETER SubscriptionId
    Azure subscription ID. If omitted, the subscription is located automatically via Azure
    Resource Graph from the resource group name.

.PARAMETER WebAppName
    Name for the new cipp web app. Defaults to (and must match) the existing Key Vault name —
    the backend resolves its Key Vault from the site name.

.PARAMETER CippUrl
    Custom domain you intend to point at the new cipp web app (e.g. 'cipp.contoso.com').
    If supplied, the post-migration summary includes the DNS records to create.

.PARAMETER ContainerImage
    Container image for cipp. Defaults to the stable public image (ghcr.io/cyberdrain/cipp:latest).

.PARAMETER TestOnly
    Validate the ARM template and detect resources without making any changes.

.PARAMETER Force
    Run the migration even if the instance appears to have already been migrated to the container architecture.

.EXAMPLE
    .\Invoke-CippMigration.ps1 -ResourceGroupName 'CIPP-RG'

.EXAMPLE
    .\Invoke-CippMigration.ps1 -ResourceGroupName 'CIPP-RG' -CippUrl 'cipp.contoso.com'

.EXAMPLE
    .\Invoke-CippMigration.ps1 -ResourceGroupName 'CIPP-RG' -TestOnly
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$SubscriptionId = '',

    [string]$WebAppName = '',

    [string]$CippUrl = '',

    [string]$ContainerImage = 'DOCKER|ghcr.io/cyberdrain/cipp:latest',

    [switch]$TestOnly,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$TemplateFilePath = Join-Path $PSScriptRoot 'cipp-migration.json'

# ── AzBobbyTables module check ────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name AzBobbyTables)) {
    Write-Warning 'AzBobbyTables module not found.'
    $install = Read-Host 'Install AzBobbyTables from PSGallery? (y/n)'
    if ($install -eq 'y') {
        Install-Module -Name AzBobbyTables -Scope CurrentUser -Force -Repository PSGallery
    } else {
        Write-Error 'AzBobbyTables is required. Install it and re-run.'
        exit 1
    }
}
Import-Module AzBobbyTables -ErrorAction Stop

# ── Auth ──────────────────────────────────────────────────────────────────────
if (!(Get-AzContext)) {
    Write-Information 'Logging into Azure...'
    Connect-AzAccount
}

# ── Resolve subscription ──────────────────────────────────────────────────────
if (-not $SubscriptionId) {
    Write-Information "Locating subscription for resource group '$ResourceGroupName'..."
    $argQuery = "Resources | where resourceGroup =~ '$ResourceGroupName' | summarize by subscriptionId | project subscriptionId"
    $argResult = Search-AzGraph -Query $argQuery -First 1
    if (-not $argResult -or -not $argResult.subscriptionId) {
        Write-Error "Resource group '$ResourceGroupName' not found in any accessible subscription. Specify -SubscriptionId explicitly."
        exit 1
    }
    $SubscriptionId = $argResult.subscriptionId
}
Write-Information "Using subscription: $SubscriptionId"
$null = Set-AzContext -SubscriptionId $SubscriptionId

# ── Storage account (location source) ────────────────────────────────────────
Write-Information "Detecting storage account in '$ResourceGroupName'..."
$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName | Select-Object -First 1
if (-not $storageAccount) {
    Write-Error "No storage account found in '$ResourceGroupName'."
    exit 1
}
$Location = $storageAccount.PrimaryLocation
Write-Information "Storage account: $($storageAccount.StorageAccountName)  location: $Location"

# ── Function app(s) ───────────────────────────────────────────────────────────
Write-Information "Detecting function apps in '$ResourceGroupName'..."
$allWebApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName
$allFunctionApps = @($allWebApps | Where-Object { $_.Kind -notmatch 'container' })
$existingCippNgApp = $allWebApps | Where-Object { $_.Kind -match 'container' } | Select-Object -First 1

$primaryFunctionApp = $allFunctionApps | Where-Object { $_.Name -notmatch '-' } | Select-Object -First 1
if (-not $primaryFunctionApp) {
    Write-Warning "No function app found in '$ResourceGroupName' — assuming already removed."
    $FuncAppName = ''
} else {
    $FuncAppName = $primaryFunctionApp.Name
    Write-Information "Primary function app: $FuncAppName"
    $offloadingApps = $allFunctionApps | Where-Object { $_.Name -match '-' }
    if ($offloadingApps) {
        Write-Information "Offloading function apps: $($offloadingApps.Name -join ', ')"
    }
}

if ($existingCippNgApp) {
    Write-Information "Existing cipp web app detected: $($existingCippNgApp.Name)"
}

# ── Already migrated? ─────────────────────────────────────────────────────────
# A completed migration leaves a container web app, the NG resource group tag,
# and no remaining function apps.
$rgTags = (Get-AzResourceGroup -Name $ResourceGroupName).Tags
$hasNgTag = $rgTags -and $rgTags['NG'] -eq 'true'
$AlreadyMigrated = ($null -ne $existingCippNgApp) -and $hasNgTag -and $allFunctionApps.Count -eq 0

if ($AlreadyMigrated) {
    Write-Information "Migration already completed: cipp web app '$($existingCippNgApp.Name)' is running, the NG tag is set, and no function apps remain."
    if ($Force.IsPresent) {
        Write-Information 'Force specified — continuing anyway.'
    } else {
        Write-Information ''
        Write-Information '=== Already Migrated — no changes made ==='
        Write-Information "Web app     : $($existingCippNgApp.Name)"
        Write-Information "cipp URL : https://$($existingCippNgApp.DefaultHostName)"
        Write-Information 'Re-run with -Force to run the migration anyway.'
        exit 0
    }
} elseif ($existingCippNgApp -or $hasNgTag) {
    Write-Information 'Partial migration detected (cipp container app or NG tag present, but old resources remain) — continuing to complete it.'
}

# ── SSO migration status ──────────────────────────────────────────────────────
# The instance must have completed its SSO migration (SSO secrets moved to the
# Key Vault) before cutting over to the container app.
Write-Information 'Checking SSO migration status...'
$storageConnString = 'DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1};EndpointSuffix=core.windows.net' -f `
    $storageAccount.StorageAccountName, `
($storageAccount | Get-AzStorageAccountKey)[0].Value

$ssoConfig = $null
try {
    $ssoCtx = New-AzDataTableContext -ConnectionString $storageConnString -TableName 'SSOMigration'
    $ssoConfig = Get-AzDataTableEntity -Context $ssoCtx -Filter "PartitionKey eq 'SSO' and RowKey eq 'MigrationConfig'" | Select-Object -First 1
} catch {
    Write-Information "  Could not read SSOMigration table: $($_.Exception.Message)"
}
$SsoStatus = if ($ssoConfig -and $ssoConfig.Status) { $ssoConfig.Status } else { '(not found)' }
Write-Information "  SSO migration status: $SsoStatus"

# Status progression in CIPP-API (Invoke-ExecSSOSetup): app_created → appid_stored → secrets_stored → complete
$SsoStageHints = @{
    '(not found)'  = 'the SSO migration has not been started'
    'app_created'  = 'the SSO app registration was created but the AppId has not been stored yet'
    'appid_stored' = 'the AppId is stored but secrets have not been created in the Key Vault yet'
    'error'        = 'the SSO migration failed and needs to be repaired'
}
$SsoReady = $SsoStatus -in @('secrets_stored', 'complete')

if (-not $SsoReady) {
    $stageHint = if ($SsoStageHints.ContainsKey($SsoStatus)) { $SsoStageHints[$SsoStatus] } else { 'unrecognized status' }
    $ssoReason = "SSO migration has not completed for '$ResourceGroupName' — status is '$SsoStatus' ($stageHint; expected 'secrets_stored' or 'complete'). Complete the SSO migration in CIPP before running this script."
    if ($ssoConfig -and $ssoConfig.LastError) {
        $ssoReason += " Last error: $($ssoConfig.LastError)"
    }
    if ($TestOnly.IsPresent) {
        Write-Warning "$ssoReason A live migration run would stop here."
    } else {
        Write-Error $ssoReason
        exit 1
    }
}

# ── App service plans ─────────────────────────────────────────────────────────
$appServicePlans = Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName

# ── Static Web App ────────────────────────────────────────────────────────────
Write-Information "Detecting Static Web App in '$ResourceGroupName'..."
$swa = Get-AzStaticWebApp -ResourceGroupName $ResourceGroupName | Select-Object -First 1
if (-not $swa) {
    Write-Error "No Static Web App found in '$ResourceGroupName'."
    exit 1
}
$SwaName = $swa.Name
Write-Information "Static Web App: $SwaName"

# ── Custom domains on SWA ─────────────────────────────────────────────────────
Write-Information "Checking for custom domains on '$SwaName'..."
$swaCustomDomains = Get-AzStaticWebAppCustomDomain -ResourceGroupName $ResourceGroupName -Name $SwaName -ErrorAction SilentlyContinue
$swaCustomDomains = @($swaCustomDomains | Where-Object { $_.DomainName -notmatch 'azurestaticapps\.net' })
if ($swaCustomDomains.Count -gt 0) {
    Write-Information "Custom domains found on SWA: $($swaCustomDomains.DomainName -join ', ')"
} else {
    Write-Information '  No custom domains on SWA.'
}

# ── Check for existing Key Vault ───────────────────────────────────────────────
Write-Information 'Checking for existing Key Vault...'
$existingKv = Get-AzKeyVault -ResourceGroupName $ResourceGroupName | Select-Object -First 1
if ($existingKv) {
    Write-Information "Found existing Key Vault '$($existingKv.VaultName)'."
} else {
    Write-Error "No Key Vault found in '$ResourceGroupName'. A Key Vault must exist before migration."
    exit 1
}

# ── Resolve target web app name ────────────────────────────────────────────────
# The web app name MUST equal the Key Vault name: the backend resolves its vault as
# $env:WEBSITE_SITE_NAME (Get-CippKeyVaultName), so a mismatch leaves the new instance
# unable to read its SAM credentials.
$TargetWebAppName = if ($WebAppName) { $WebAppName } else { $existingKv.VaultName }
if ($TargetWebAppName -ne $existingKv.VaultName) {
    Write-Error "WebAppName '$TargetWebAppName' does not match the existing Key Vault name '$($existingKv.VaultName)'. The web app and Key Vault must share the same name (the backend resolves its vault from the site name). Omit -WebAppName to use the Key Vault name."
    exit 1
}

# ── ARM template test ─────────────────────────────────────────────────────────
$DeploymentParams = @{
    ResourceGroupName          = $ResourceGroupName
    TemplateFile               = $TemplateFilePath
    location                   = $Location
    containerImage             = $ContainerImage
    existingStorageAccountName = $storageAccount.StorageAccountName
    existingKeyVaultName       = $existingKv.VaultName
    webAppName                 = $TargetWebAppName
}

Write-Information 'Testing ARM template...'
try {
    $TestResult = Test-AzResourceGroupDeployment @DeploymentParams -ErrorAction Stop
} catch {
    Write-Error "ARM template test failed: $($_.Exception.Message)"
    exit 1
}

if ($TestResult.Code) {
    Write-Error "ARM template validation failed: $($TestResult.Code) — $($TestResult.Message)"
    exit 1
}
Write-Information 'ARM template test passed.'

if ($TestOnly.IsPresent) {
    Write-Information ''
    Write-Information '=== TestOnly mode — no changes made ==='
    Write-Information "Resource group  : $ResourceGroupName"
    Write-Information "Location        : $Location"
    Write-Information "Storage account : $($storageAccount.StorageAccountName)"
    Write-Information "Key Vault       : $($existingKv.VaultName)"
    Write-Information "SSO migration   : $SsoStatus$(if (-not $SsoReady) { ' (NOT READY - live run would stop)' })"
    Write-Information "Function app    : $(if ($FuncAppName) { $FuncAppName } else { '(not found - already removed)' })"
    Write-Information "Existing ng app : $(if ($existingCippNgApp) { $existingCippNgApp.Name } else { '(none)' })"
    Write-Information "New web app name : $TargetWebAppName"
    Write-Information "SWA (to delete) : $SwaName"
    if ($swaCustomDomains.Count -gt 0) {
        Write-Information "SWA custom domains (to remove): $($swaCustomDomains.DomainName -join ', ')"
    }
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# MIGRATE SWA USERS
# ══════════════════════════════════════════════════════════════════════════════

Write-Information 'Migrating SWA role assignments to allowedUsers table...'
$aadUsersResponse = Invoke-AzRestMethod `
    -Method POST `
    -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName/authproviders/all/listUsers?api-version=2022-09-01"
$swaUsers = ($aadUsersResponse.Content | ConvertFrom-Json).value

$tableCtx = New-AzDataTableContext -ConnectionString $storageConnString -TableName 'allowedUsers'

# Valid roles = CIPP built-ins + this instance's custom roles (CustomRoles table,
# canonical casing from RowKey — custom role lookups are case-sensitive). SWA
# invites often carry display-name variants ('full editor') or roles that no
# longer exist; migrating those pollutes the permission checks.
$roleMap = @{}
foreach ($r in @('superadmin', 'admin', 'editor', 'readonly')) { $roleMap[$r] = $r }
try {
    $customRolesCtx = New-AzDataTableContext -ConnectionString $storageConnString -TableName 'CustomRoles'
    foreach ($row in @(Get-AzDataTableEntity -Context $customRolesCtx -ErrorAction Stop)) {
        if ($row.RowKey) { $roleMap[$row.RowKey] = $row.RowKey }
    }
} catch {
    Write-Information 'No CustomRoles table found — validating roles against CIPP built-ins only.'
}

if ($swaUsers.Count -gt 0) {
    $migrated = 0
    $skipped = 0
    foreach ($u in $swaUsers) {
        $email = $u.properties.displayName.ToLower()
        # roles may be a comma-separated string or an array depending on API version
        $rawRoles = $u.properties.roles
        if ($rawRoles -is [string]) {
            $roles = @($rawRoles -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -notin 'authenticated', 'anonymous' })
        } else {
            $roles = @($rawRoles | Where-Object { $_ -notin 'authenticated', 'anonymous' })
        }

        # Keep only roles that actually exist, mapping display-name variants with
        # spaces ('full editor') onto their real role name; drop the rest.
        $resolved = [System.Collections.Generic.List[string]]::new()
        $dropped = [System.Collections.Generic.List[string]]::new()
        foreach ($role in $roles) {
            $canonical = $roleMap[$role] ?? $roleMap[($role -replace '\s', '')]
            if ($canonical) {
                if ($resolved -notcontains $canonical) { $resolved.Add($canonical) }
            } else {
                $dropped.Add($role)
            }
        }
        if ($dropped.Count -gt 0) {
            Write-Information "  Dropped non-existent role(s) for ${email}: $($dropped -join ', ')"
        }
        $roles = @($resolved)

        # superadmin supersedes everything — carrying additional roles alongside it
        # interferes with the high-privilege permission checks, so migrate
        # superadmins with that role only
        if ($roles -contains 'superadmin') {
            $roles = @('superadmin')
        }

        if (-not $email -or $roles.Count -eq 0) {
            $skipped++
            continue
        }

        # Build JSON manually — ConvertTo-Json unrolls multi-item arrays in the pipeline,
        # producing a string[] instead of a single string, which AzBobbyTables rejects.
        $rolesJson = '[' + (($roles | ForEach-Object { "`"$_`"" }) -join ',') + ']'

        $entity = [pscustomobject]@{
            PartitionKey = 'User'
            RowKey       = $email
            AutoRoles    = '[]'
            ManualRoles  = $rolesJson
            Roles        = $rolesJson
            Source       = 'Manual'
        }

        try {
            if ($PSCmdlet.ShouldProcess($email, 'Write user to allowedUsers table')) {
                Add-AzDataTableEntity -Context $tableCtx -Entity $entity -CreateTableIfNotExists -Force
                Write-Information "  Migrated: $email ($rolesJson)"
                $migrated++
            }
        } catch {
            Write-Warning "  Failed to migrate $email`: $($_.Exception.Message)"
        }
    }
    Write-Information "SWA user migration complete: $migrated migrated, $skipped skipped (no roles or no email)."
} else {
    Write-Information '  No SWA users found to migrate.'
}

# ══════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT
# ══════════════════════════════════════════════════════════════════════════════

# ── Remove SWA linked backend ─────────────────────────────────────────────────
Write-Information "Removing SWA linked backend from '$SwaName'..."
$backendResponse = Invoke-AzRestMethod `
    -Method GET `
    -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName/builds/default/linkedBackends?api-version=2022-09-01"
$backend = ($backendResponse.Content | ConvertFrom-Json).value | Select-Object -First 1

if ($backend.id) {
    Write-Information "  Unlinking backend: $($backend.name)"
    if ($PSCmdlet.ShouldProcess($backend.name, 'Unlink SWA backend')) {
        $null = Invoke-AzRestMethod `
            -Method DELETE `
            -Uri "https://management.azure.com$($backend.id)?isCleaningAuthConfig=false&api-version=2022-09-01"
    }
} else {
    Write-Information '  No linked backend found.'
}

# ── Remove old function apps and app service plans ────────────────────────────
if ($allFunctionApps.Count -gt 0) {
    Write-Information 'Removing old function apps and app service plans...'
    $FunctionsToDelete = [System.Collections.Generic.List[psobject]]::new()
    foreach ($fa in $allFunctionApps) { $FunctionsToDelete.Add($fa) }

    foreach ($fa in $FunctionsToDelete) {
        Write-Information "  Removing function app: $($fa.Name)"
        if ($PSCmdlet.ShouldProcess($fa.Name, 'Remove function app')) {
            Remove-AzWebApp -Name $fa.Name -ResourceGroupName $ResourceGroupName -Force
        }

        $plan = $appServicePlans | Where-Object { $_.Id -eq $fa.ServerFarmId }
        if ($plan) {
            if ($plan.ResourceGroup -ne $ResourceGroupName) {
                Write-Information "  Skipping shared app service plan '$($plan.Name)' (in resource group '$($plan.ResourceGroup)')."
            } else {
                do {
                    Write-Information "  Removing app service plan: $($plan.Name)"
                    if ($PSCmdlet.ShouldProcess($plan.Name, 'Remove app service plan')) {
                        Remove-AzAppServicePlan -Name $plan.Name -ResourceGroupName $ResourceGroupName -Force
                    }
                    Start-Sleep -Seconds 5
                    $plan = Get-AzAppServicePlan -Name $plan.Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                } while ($plan)
            }
        }
    }
} else {
    Write-Information 'No function apps to remove — skipping.'
}

# ── Remove Application Insights and smart detector alert rules ────────────────
Write-Information 'Checking for Application Insights and smart detector alert rules to remove...'

# Smart detector alert rules first — they reference the App Insights components
$smartDetectorRules = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'microsoft.alertsmanagement/smartDetectorAlertRules' -ErrorAction SilentlyContinue)
foreach ($rule in $smartDetectorRules) {
    Write-Information "  Removing smart detector alert rule: $($rule.Name)"
    if ($PSCmdlet.ShouldProcess($rule.Name, 'Remove smart detector alert rule')) {
        try {
            $null = Remove-AzResource -ResourceId $rule.ResourceId -Force
        } catch {
            Write-Warning "  Failed to remove alert rule '$($rule.Name)': $($_.Exception.Message)"
        }
    }
}

$appInsights = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Insights/components' -ErrorAction SilentlyContinue)
foreach ($ai in $appInsights) {
    Write-Information "  Removing Application Insights: $($ai.Name)"
    if ($PSCmdlet.ShouldProcess($ai.Name, 'Remove Application Insights component')) {
        try {
            $null = Remove-AzResource -ResourceId $ai.ResourceId -Force
        } catch {
            Write-Warning "  Failed to remove Application Insights '$($ai.Name)': $($_.Exception.Message)"
        }
    }
}

if ($smartDetectorRules.Count -eq 0 -and $appInsights.Count -eq 0) {
    Write-Information '  No Application Insights or alert rules found.'
}

# ── Remove storage file shares ────────────────────────────────────────────────
Write-Information 'Checking for file shares to remove...'
$storageCtx = $storageAccount.Context
$fileShares = Get-AzStorageShare -Context $storageCtx -ErrorAction SilentlyContinue
if ($fileShares) {
    foreach ($share in $fileShares) {
        Write-Information "  Removing file share: $($share.Name)"
        if ($PSCmdlet.ShouldProcess($share.Name, 'Remove storage file share')) {
            Remove-AzStorageShare -Context $storageCtx -Name $share.Name -Force
        }
    }
} else {
    Write-Information '  No file shares found.'
}

# ── Deploy cipp ─────────────────────────────────────────────────────────────
Write-Information 'Deploying cipp ARM template...'
$Deployment = $null
if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Deploy cipp ARM template')) {
    $Deployment = New-AzResourceGroupDeployment -Name 'cipp-migration' @DeploymentParams -Verbose -ErrorAction Stop
    Write-Information 'Deployment completed.'
}

$NewHostname = $Deployment.Outputs['hostname'].Value
$NewWebAppName = $Deployment.Outputs['webAppName'].Value
$NewKvName = $existingKv.VaultName

if ($NewHostname) {
    Write-Information "cipp hostname : $NewHostname"
    Write-Information "cipp URL      : https://$NewHostname"
}
Write-Information "Key Vault        : $NewKvName"

# ── Retrieve DNS record values from the new web app ──────────────────────────
$NewInboundIp = ''
$NewDomainVerificationId = ''
if ($NewWebAppName) {
    Write-Information "Retrieving DNS record values from '$NewWebAppName'..."
    $siteResponse = Invoke-AzRestMethod `
        -Method GET `
        -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$NewWebAppName`?api-version=2024-11-01"
    $siteProperties = ($siteResponse.Content | ConvertFrom-Json).properties
    $NewInboundIp = $siteProperties.inboundIpAddress
    $NewDomainVerificationId = $siteProperties.customDomainVerificationId
    Write-Information "  Inbound IP (A record)        : $NewInboundIp"
    Write-Information "  Domain verification ID (TXT) : $NewDomainVerificationId"
}

# ── Remove custom domains from SWA before deletion ───────────────────────────
if ($swaCustomDomains.Count -gt 0) {
    Write-Information "Removing custom domains from '$SwaName' before deletion..."
    foreach ($domain in $swaCustomDomains) {
        Write-Information "  Removing custom domain: $($domain.DomainName)"
        if ($PSCmdlet.ShouldProcess($domain.DomainName, 'Remove SWA custom domain')) {
            $null = Invoke-AzRestMethod `
                -Method DELETE `
                -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName/customDomains/$($domain.DomainName)?api-version=2022-09-01"
        }
    }

    # Poll until all custom domains are gone (deletion is async)
    Write-Information '  Waiting for custom domain removal to complete...'
    $pollAttempts = 0
    $maxPollAttempts = 24  # 2 minutes at 5s intervals
    do {
        Start-Sleep -Seconds 5
        $remaining = Get-AzStaticWebAppCustomDomain -ResourceGroupName $ResourceGroupName -Name $SwaName -ErrorAction SilentlyContinue |
            Where-Object { $_.DomainName -notmatch 'azurestaticapps\.net' }
        $pollAttempts++
        if ($remaining) {
            Write-Information "  Still waiting on: $($remaining.DomainName -join ', ') ($($pollAttempts * 5)s elapsed)"
        }
    } while ($remaining -and $pollAttempts -lt $maxPollAttempts)

    if ($remaining) {
        Write-Warning "Custom domains did not finish removing after $($maxPollAttempts * 5)s. SWA deletion may fail."
    } else {
        Write-Information '  All custom domains removed.'
    }
}

# ── Delete Static Web App ─────────────────────────────────────────────────────
Write-Information "Deleting Static Web App '$SwaName'..."
if ($PSCmdlet.ShouldProcess($SwaName, 'Delete Static Web App')) {
    $null = Invoke-AzRestMethod `
        -Method DELETE `
        -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName`?api-version=2022-09-01"
    Write-Information "  '$SwaName' deleted."
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Information ''
Write-Information '=== Migration Complete ==='
Write-Information "CIPP hostname : https://$NewHostname"
Write-Information "Web app name     : $NewWebAppName"
Write-Information "Key Vault        : $NewKvName"
Write-Information "Static Web App '$SwaName' has been deleted."

$domainsToPoint = [System.Collections.Generic.List[string]]::new()
foreach ($domain in $swaCustomDomains) { $domainsToPoint.Add($domain.DomainName) }
if ($CippUrl -and $domainsToPoint -notcontains $CippUrl) { $domainsToPoint.Add($CippUrl) }

if ($domainsToPoint.Count -gt 0) {
    Write-Information ''
    Write-Information '=== Next Steps: Custom Domain ==='
    Write-Information "Update your DNS — create the following records, then add each domain in the App Service blade for '$NewWebAppName':"
    foreach ($domain in $domainsToPoint) {
        $source = if ($swaCustomDomains.DomainName -contains $domain) { ' (was on SWA)' } else { '' }
        Write-Information "Domain: $domain$source"
        Write-Information '  A record'
        Write-Information "    Name  : $domain"
        Write-Information "    Value : $NewInboundIp"
        if ($NewDomainVerificationId) {
            Write-Information '  TXT record (domain verification)'
            Write-Information "    Name  : asuid.$domain"
            Write-Information "    Value : $NewDomainVerificationId"
        }
        Write-Information ''
    }
}
