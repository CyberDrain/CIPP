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

.PARAMETER SkipIamCheck
    Skip the Owner permission check. The migration will still fail at the point a missing
    permission is needed — only use this if the check itself cannot run in your environment.

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

    [switch]$Force,

    [switch]$SkipIamCheck
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$TemplateFilePath = Join-Path $PSScriptRoot 'cipp-migration.json'

# The Az.Websites static-site cmdlets print an upcoming-breaking-change banner that drowns
# out this script's output. Neither $env:SuppressAzurePowerShellBreakingChangeWarnings nor
# Update-AzConfig -DisplayBreakingChangeWarning suppresses it for these autorest-generated
# cmdlets, so each call passes -WarningAction SilentlyContinue instead. Kept per-call rather
# than script-wide so this script's own Write-Warning output still reaches the user.

# ── Transient-error retry helpers ─────────────────────────────────────────────
# Transient control-plane faults (5xx, 429, HttpClient timeouts/cancellations). Every
# wrapped call is a read or idempotent, so re-issuing is safe; other errors re-throw.
$TransientAzurePattern = 'Internal\s*Server\s*Error|HttpClient\.Timeout|An error occurred while sending the request|request was canceled|operation was canceled|timed out|TooManyRequests|ServiceUnavailable|GatewayTimeout|BadGateway|temporarily unavailable|please try again'

function Invoke-AzWithRetry {
    # Retries a scriptblock through transient Azure control-plane malfunctions.
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string]$OperationName = 'Azure operation',
        [int]$MaxRetries = 5,
        [int]$DelaySeconds = 15
    )
    $transient = $TransientAzurePattern
    $attempt = 0
    while ($true) {
        try {
            return & $ScriptBlock
        } catch {
            if ($_.Exception.Message -match $transient -and $attempt -lt $MaxRetries) {
                $attempt++
                Write-Information "  $OperationName hit a transient Azure error — retrying in ${DelaySeconds}s ($attempt/$MaxRetries)... ($($_.Exception.Message -split "`n" | Select-Object -First 1))"
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            throw
        }
    }
}

function Invoke-AzRestMethodWithRetry {
    # Retries transient transport failures on Invoke-AzRestMethod. Always passes
    # -WhatIf:$false: reads must run under -WhatIf; mutating call sites are
    # already ShouldProcess-guarded.
    param(
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [string]$Payload,
        [int]$MaxRetries = 4,
        [int]$DelaySeconds = 10
    )
    $RestArgs = @{ Method = $Method; Uri = $Uri }
    if ($PSBoundParameters.ContainsKey('Payload')) { $RestArgs.Payload = $Payload }
    $transient = $TransientAzurePattern
    $attempt = 0
    while ($true) {
        try {
            return Invoke-AzRestMethod @RestArgs -WhatIf:$false
        } catch {
            if ($_.Exception.Message -match $transient -and $attempt -lt $MaxRetries) {
                $attempt++
                Write-Information "  $OperationName hit a transient error — retrying in ${DelaySeconds}s ($attempt/$MaxRetries)..."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            throw
        }
    }
}

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
# -WhatIf:$false — selecting the subscription is not a change. Without this, -WhatIf
# skips the context switch and every subsequent lookup runs against the wrong subscription.
$null = Set-AzContext -SubscriptionId $SubscriptionId -WhatIf:$false

# ── Permission check ──────────────────────────────────────────────────────────
# The migration creates and deletes resources across Web, Storage, Key Vault and
# Insights, and cipp-migration.json assigns Contributor on the new web app to its
# own managed identity — that last part needs Microsoft.Authorization/roleAssignments/write,
# which Contributor does not have. Rather than enumerate every action, require Owner
# on the resource group and fail fast, before anything has been deleted.
$RgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

if ($SkipIamCheck.IsPresent) {
    Write-Warning 'Skipping the Owner permission check (-SkipIamCheck). A missing permission will surface mid-migration, after resources have already been deleted.'
} else {
    Write-Information "Checking permissions on '$ResourceGroupName'..."

    # The ARM token's 'oid' claim identifies the caller regardless of principal type
    # (user, service principal, managed identity) and needs no Graph permissions.
    $callerObjectId = $null
    try {
        $tokenObj = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -ErrorAction Stop
        $rawToken = if ($tokenObj.Token -is [securestring]) { ConvertFrom-SecureString $tokenObj.Token -AsPlainText } else { $tokenObj.Token }
        $payload = $rawToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $callerObjectId = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json).oid
    } catch {
        Write-Verbose "Could not read object ID from access token: $($_.Exception.Message)"
    }
    Write-Information "  Signed in as: $((Get-AzContext).Account.Id)"

    # Owner is 'can do anything, including assign roles'. Probing those two actions
    # via checkAccess covers built-in Owner, an equivalent custom role, and
    # Contributor + User Access Administrator — and honours deny assignments.
    $OwnerProbeActions = @('Microsoft.Authorization/roleAssignments/write', 'Microsoft.Web/sites/delete')
    $HasOwnerAccess = $null   # $null = could not determine

    if ($callerObjectId) {
        try {
            $body = @{
                Subject  = @{ Attributes = @{ ObjectId = $callerObjectId } }
                Actions  = @($OwnerProbeActions | ForEach-Object { @{ Id = $_; IsDataAction = $false } })
                Resource = @{ Id = $RgScope }
            } | ConvertTo-Json -Depth 6

            # -WhatIf:$false — checkAccess is a read; it must run even under -WhatIf
            $checkAccess = Invoke-AzRestMethod `
                -Method POST `
                -Uri "https://management.azure.com$RgScope/providers/Microsoft.Authorization/checkAccess?api-version=2018-09-01-preview" `
                -Payload $body `
                -WhatIf:$false

            if ($checkAccess.StatusCode -ge 200 -and $checkAccess.StatusCode -lt 300) {
                # The API returns a bare array of decisions; some versions wrap it
                # in an 'accessDecisions' property. Handle both.
                $parsed = $checkAccess.Content | ConvertFrom-Json
                # NB: test for an array FIRST — on an array, $parsed.accessDecisions
                # member-enumerates to an empty array, which is not $null.
                $decisions = @(if ($parsed -is [System.Array]) { $parsed } elseif ($parsed.accessDecisions) { $parsed.accessDecisions } else { $parsed })
                $decisions = @($decisions | Where-Object { $_.accessDecision })
                if ($decisions.Count -eq $OwnerProbeActions.Count) {
                    $HasOwnerAccess = -not @($decisions | Where-Object { $_.accessDecision -ne 'Allowed' }).Count
                } else {
                    Write-Verbose "checkAccess returned $($decisions.Count) decisions for $($OwnerProbeActions.Count) actions — ignoring."
                }
            } else {
                Write-Verbose "checkAccess returned HTTP $($checkAccess.StatusCode): $($checkAccess.Content)"
            }
        } catch {
            Write-Verbose "checkAccess call failed: $($_.Exception.Message)"
        }
    }

    # Fallback: look for an Owner (or wildcard-action) assignment at or above the scope.
    if ($null -eq $HasOwnerAccess) {
        try {
            $assignments = @(Get-AzRoleAssignment -Scope $RgScope -ErrorAction Stop |
                    Where-Object { -not $callerObjectId -or $_.ObjectId -eq $callerObjectId })
            $HasOwnerAccess = [bool](@($assignments | Where-Object {
                        $_.RoleDefinitionName -in @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')
                    }).Count)
        } catch {
            Write-Verbose "Role assignment lookup failed: $($_.Exception.Message)"
        }
    }

    if ($null -eq $HasOwnerAccess) {
        Write-Warning "Could not determine your permissions on '$ResourceGroupName'. Owner on the resource group is required — the migration will fail partway through without it."
    } elseif (-not $HasOwnerAccess) {
        $iamReason = "Owner on resource group '$ResourceGroupName' is required to run this migration. The migration deletes the function apps, app service plans, Application Insights components and Static Web App, and grants the new web app's managed identity Contributor on itself — Contributor alone cannot create that role assignment. Grant Owner (or Contributor + User Access Administrator) on '$ResourceGroupName' and re-run."
        if ($TestOnly.IsPresent) {
            Write-Warning "$iamReason A live migration run would stop here."
        } else {
            Write-Error $iamReason
            exit 1
        }
    } else {
        Write-Information '  Owner-level access confirmed.'
    }
}

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

# A missing SSOMigration row does not always mean the migration was never run — an
# instance already cut over to the container app has working SSO via Easy Auth, and
# the tracking row may have been cleaned up or never written. If Easy Auth is
# configured on the container app with an enabled AAD provider, SSO is done in the
# only sense that matters here. Other statuses still indicate a genuinely incomplete
# migration, so this fallback applies to '(not found)' only.
$SsoSatisfiedByEasyAuth = $false
if (-not $SsoReady -and $SsoStatus -eq '(not found)' -and $existingCippNgApp) {
    Write-Information "  No SSOMigration record — checking Easy Auth on '$($existingCippNgApp.Name)'..."
    try {
        $authResponse = Invoke-AzRestMethod `
            -Method GET `
            -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$($existingCippNgApp.Name)/config/authsettingsV2?api-version=2024-11-01" `
            -WhatIf:$false

        if ($authResponse.StatusCode -ge 200 -and $authResponse.StatusCode -lt 300) {
            $authProps = ($authResponse.Content | ConvertFrom-Json).properties
            $aad = $authProps.identityProviders.azureActiveDirectory
            if ($authProps.platform.enabled -and $aad.enabled -and $aad.registration.clientId) {
                $SsoSatisfiedByEasyAuth = $true
                $SsoReady = $true
                Write-Information "  Easy Auth is configured (AAD client ID $($aad.registration.clientId)) — treating SSO as complete."
            } else {
                Write-Information "  Easy Auth is not fully configured (platform enabled: $([bool]$authProps.platform.enabled), AAD enabled: $([bool]$aad.enabled), client ID set: $([bool]$aad.registration.clientId))."
            }
        } else {
            Write-Information "  Could not read Easy Auth config: HTTP $($authResponse.StatusCode)."
        }
    } catch {
        Write-Information "  Could not read Easy Auth config: $($_.Exception.Message)"
    }
}

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
$appServicePlans = Invoke-AzWithRetry -OperationName "Get-AzAppServicePlan in '$ResourceGroupName'" -ScriptBlock {
    Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName
}

# ── Static Web App ────────────────────────────────────────────────────────────
Write-Information "Detecting Static Web App in '$ResourceGroupName'..."
$swa = Get-AzStaticWebApp -ResourceGroupName $ResourceGroupName -WarningAction SilentlyContinue | Select-Object -First 1
# A missing SWA is not fatal — a re-run or a partially completed migration has already
# deleted it. Every SWA-dependent step below is skipped instead.
$swaCustomDomains = @()
if ($swa) {
    $SwaName = $swa.Name
    Write-Information "Static Web App: $SwaName"

    # ── Custom domains on SWA ─────────────────────────────────────────────────
    Write-Information "Checking for custom domains on '$SwaName'..."
    $swaCustomDomains = Get-AzStaticWebAppCustomDomain -ResourceGroupName $ResourceGroupName -Name $SwaName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $swaCustomDomains = @($swaCustomDomains | Where-Object { $_.DomainName -notmatch 'azurestaticapps\.net' })
    if ($swaCustomDomains.Count -gt 0) {
        Write-Information "Custom domains found on SWA: $($swaCustomDomains.DomainName -join ', ')"
    } else {
        Write-Information '  No custom domains on SWA.'
    }
} else {
    $SwaName = ''
    Write-Warning "No Static Web App found in '$ResourceGroupName' — assuming already removed. SWA user migration and teardown will be skipped."
}

# ── Check for existing Key Vault ───────────────────────────────────────────────
Write-Information 'Checking for existing Key Vault...'
$existingKv = Invoke-AzWithRetry -OperationName "Get-AzKeyVault in '$ResourceGroupName'" -ScriptBlock {
    Get-AzKeyVault -ResourceGroupName $ResourceGroupName
} | Select-Object -First 1
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

# An instance that is already on the container architecture has everything the template
# would create. Re-deploying it is at best a no-op and at worst harmful — it asks for a
# second app service plan, which fails outright in subscriptions with no spare VM quota.
# With -Force the remaining cleanup steps still run; only the deployment is skipped.
$SkipDeployment = $AlreadyMigrated

if ($SkipDeployment) {
    Write-Information 'Already migrated — skipping ARM template test and deployment; only leftover cleanup will run.'
} else {
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
}

if ($TestOnly.IsPresent) {
    Write-Information ''
    Write-Information '=== TestOnly mode — no changes made ==='
    Write-Information "Resource group  : $ResourceGroupName"
    Write-Information "Location        : $Location"
    Write-Information "Storage account : $($storageAccount.StorageAccountName)"
    Write-Information "Key Vault       : $($existingKv.VaultName)"
    Write-Information "Permissions     : $(if ($SkipIamCheck.IsPresent) { '(check skipped)' } elseif ($null -eq $HasOwnerAccess) { '(could not determine)' } elseif ($HasOwnerAccess) { 'Owner' } else { 'NOT Owner (NOT READY - live run would stop)' })"
    Write-Information "SSO migration   : $SsoStatus$(if ($SsoSatisfiedByEasyAuth) { ' (Easy Auth configured - OK)' } elseif (-not $SsoReady) { ' (NOT READY - live run would stop)' })"
    Write-Information "Function app    : $(if ($FuncAppName) { $FuncAppName } else { '(not found - already removed)' })"
    Write-Information "Existing ng app : $(if ($existingCippNgApp) { $existingCippNgApp.Name } else { '(none)' })"
    Write-Information "New web app name : $TargetWebAppName"
    Write-Information "ARM deployment  : $(if ($SkipDeployment) { '(skipped - already migrated)' } else { 'would deploy' })"
    Write-Information "SWA (to delete) : $(if ($SwaName) { $SwaName } else { '(not found - already removed)' })"
    if ($swaCustomDomains.Count -gt 0) {
        Write-Information "SWA custom domains (to remove): $($swaCustomDomains.DomainName -join ', ')"
    }
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# MIGRATE SWA USERS
# ══════════════════════════════════════════════════════════════════════════════

$swaUsers = @()
if ($swa) {
    Write-Information 'Migrating SWA role assignments to allowedUsers table...'
    # listUsers is a read despite being a POST
    $aadUsersResponse = Invoke-AzRestMethodWithRetry `
        -OperationName 'Listing SWA users' `
        -Method POST `
        -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName/authproviders/all/listUsers?api-version=2022-09-01"
    $swaUsers = @(($aadUsersResponse.Content | ConvertFrom-Json).value)
} else {
    Write-Information 'No Static Web App — skipping SWA user migration (allowedUsers was populated on the original run).'
}

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
if ($swa) {
    Write-Information "Removing SWA linked backend from '$SwaName'..."
    $backendResponse = Invoke-AzRestMethodWithRetry `
        -OperationName 'Listing linked backends' `
        -Method GET `
        -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName/builds/default/linkedBackends?api-version=2022-09-01"
    $backend = ($backendResponse.Content | ConvertFrom-Json).value | Select-Object -First 1

    if ($backend.id) {
        Write-Information "  Unlinking backend: $($backend.name)"
        if ($PSCmdlet.ShouldProcess($backend.name, 'Unlink SWA backend')) {
            $null = Invoke-AzRestMethodWithRetry `
                -OperationName 'Unlinking backend' `
                -Method DELETE `
                -Uri "https://management.azure.com$($backend.id)?isCleaningAuthConfig=false&api-version=2022-09-01"
        }
    } else {
        Write-Information '  No linked backend found.'
    }
}

# ── Remove old function apps and app service plans ────────────────────────────
if ($allFunctionApps.Count -gt 0) {
    Write-Information 'Removing old function apps and app service plans...'

    # Phase 1 — delete every function app first: offloading apps share the primary's
    # plan, and a plan can't be removed until all of its apps are gone.
    foreach ($fa in $allFunctionApps) {
        Write-Information "  Removing function app: $($fa.Name)"
        if ($PSCmdlet.ShouldProcess($fa.Name, 'Remove function app')) {
            # Still fatal on a genuine failure: the new web app reuses this name.
            Invoke-AzWithRetry -OperationName "Removing function app '$($fa.Name)'" -ScriptBlock {
                Remove-AzWebApp -Name $fa.Name -ResourceGroupName $ResourceGroupName -Force
            }
        }
    }

    # Phase 2 — remove the now-orphaned plans (unique; skip plans in another resource group).
    $funcPlanIds = @($allFunctionApps | ForEach-Object { $_.ServerFarmId } | Sort-Object -Unique)
    $plansToRemove = @($appServicePlans | Where-Object { $_.Id -in $funcPlanIds })
    foreach ($plan in $plansToRemove) {
        if ($plan.ResourceGroup -ne $ResourceGroupName) {
            Write-Information "  Skipping shared app service plan '$($plan.Name)' (in resource group '$($plan.ResourceGroup)')."
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($plan.Name, 'Remove app service plan')) { continue }
        # Function app deletion is async: the plan returns Conflict until its apps
        # finish detaching, so retry (bounded).
        $planName = $plan.Name
        $planRetries = 0
        $maxPlanRetries = 18   # ~3 min at 10s between attempts
        while ($true) {
            if (-not (Get-AzAppServicePlan -Name $planName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)) {
                Write-Information "  App service plan '$planName' removed."
                break
            }
            try {
                Write-Information "  Removing app service plan: $planName"
                Remove-AzAppServicePlan -Name $planName -ResourceGroupName $ResourceGroupName -Force -ErrorAction Stop
            } catch {
                # Conflict = the just-deleted function apps are still detaching.
                if ($_.Exception.Message -match 'Conflict' -and $planRetries -lt $maxPlanRetries) {
                    $planRetries++
                    Write-Information "  Plan '$planName' still has a resource attached (function app deletion in progress) — retrying in 10s ($planRetries/$maxPlanRetries)..."
                    Start-Sleep -Seconds 10
                    continue
                }
                # Still Conflict with sites attached: other apps run on it — leave it.
                if ($_.Exception.Message -match 'Conflict') {
                    $livePlan = Get-AzAppServicePlan -Name $planName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
                    if ($livePlan -and [int]$livePlan.NumberOfSites -gt 0) {
                        Write-Warning "Plan '$planName' still hosts $($livePlan.NumberOfSites) app(s) — left in place; remove it manually once empty."
                        break
                    }
                }
                # Not fatal: the apps are gone and the deploy can proceed.
                Write-Warning "Could not remove plan '$planName': $($_.Exception.Message) — left in place; remove it manually."
                break
            }
            Start-Sleep -Seconds 5
        }
    }
} else {
    Write-Information 'No function apps to remove — skipping.'
}

# ── Remove Application Insights and smart detector alert rules ────────────────
Write-Information 'Checking for Application Insights and smart detector alert rules to remove...'

# Smart detector alert rules first — they reference the App Insights components.
# From here to the deploy nothing may throw fatally: the function apps are already
# gone, so any abort here is downtime over cleanup.
$smartDetectorRules = @()
try {
    $smartDetectorRules = @(Invoke-AzWithRetry -OperationName 'Listing smart detector rules' -ScriptBlock {
            Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'microsoft.alertsmanagement/smartDetectorAlertRules' -ErrorAction SilentlyContinue
        })
} catch { Write-Warning "  Could not list smart detector rules: $($_.Exception.Message)" }
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

$appInsights = @()
try {
    $appInsights = @(Invoke-AzWithRetry -OperationName 'Listing Application Insights' -ScriptBlock {
            Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.Insights/components' -ErrorAction SilentlyContinue
        })
} catch { Write-Warning "  Could not list Application Insights: $($_.Exception.Message)" }
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
# Never fatal — a leftover share costs cents. Data-plane cmdlets throw transport
# errors regardless of -ErrorAction, so retry, then warn and move on.
Write-Information 'Checking for file shares to remove...'
try {
    $storageCtx = $storageAccount.Context
    $fileShares = @(Invoke-AzWithRetry -OperationName 'Listing file shares' -MaxRetries 3 -DelaySeconds 5 -ScriptBlock {
            Get-AzStorageShare -Context $storageCtx -ErrorAction Stop
        })
    if ($fileShares.Count) {
        foreach ($share in $fileShares) {
            Write-Information "  Removing file share: $($share.Name)"
            if ($PSCmdlet.ShouldProcess($share.Name, 'Remove storage file share')) {
                try {
                    Remove-AzStorageShare -Context $storageCtx -Name $share.Name -Force
                } catch {
                    Write-Warning "  Failed to remove file share '$($share.Name)': $($_.Exception.Message)"
                }
            }
        }
    } else {
        Write-Information '  No file shares found.'
    }
} catch {
    Write-Warning "  Could not enumerate file shares: $($_.Exception.Message)"
}

# ── Remove stale role assignments on the target site scope ───────────────────
# The legacy template granted the function app Contributor on itself, and Azure removes
# a deleted site's role assignments asynchronously - often minutes after the delete
# returns. Deploying a same-named site while that row lingers fails the deploy
# (RoleAssignmentUpdateNotPermitted) or loses the new grant to the late cleanup.
# The site is about to be (re)created, so any assignment scoped exactly to it is
# stale; inherited (resource group / subscription) rows are left alone.
if (-not $SkipDeployment) {
    $targetSiteScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$TargetWebAppName"
    $targetSiteExists = [bool](Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $TargetWebAppName -ErrorAction SilentlyContinue)
    if ($targetSiteExists) {
        Write-Information "Web app '$TargetWebAppName' already exists - keeping its role assignments."
    } else {
        Write-Information "Checking for stale role assignments on '$TargetWebAppName'..."
        $staleAssignments = @()
        try {
            $staleAssignments = @(Invoke-AzWithRetry -OperationName 'Listing role assignments' -ScriptBlock {
                    Get-AzRoleAssignment -Scope $targetSiteScope -ErrorAction Stop
                } | Where-Object { $_.Scope -eq $targetSiteScope })
        } catch {
            # Some Az versions 404 the list when the resource behind the scope is gone —
            # that just means nothing lingers. Anything else: warn and proceed; aborting
            # here (old apps deleted, nothing deployed) is guaranteed downtime.
            if ($_.Exception.Message -notmatch 'NotFound') {
                Write-Warning "  Could not list role assignments on '$TargetWebAppName': $($_.Exception.Message) — continuing; the deploy may fail if a stale assignment lingers."
            }
        }
        foreach ($assignment in $staleAssignments) {
            Write-Information "  Removing stale '$($assignment.RoleDefinitionName)' assignment for $($assignment.ObjectType) $($assignment.ObjectId)"
            if ($PSCmdlet.ShouldProcess($assignment.RoleAssignmentId, 'Remove stale role assignment')) {
                try {
                    Invoke-AzWithRetry -OperationName 'Removing stale role assignment' -ScriptBlock {
                        Remove-AzRoleAssignment -InputObject $assignment -ErrorAction Stop
                    }
                } catch {
                    # NotFound: Azure's own cleanup beat us to it. Anything else: warn —
                    # aborting here is guaranteed downtime, a lingering row only might fail the deploy.
                    if ($_.Exception.Message -notmatch 'does not exist|NotFound') {
                        Write-Warning "  Could not remove stale assignment $($assignment.RoleAssignmentId): $($_.Exception.Message) — continuing."
                    }
                }
            }
        }
        if ($staleAssignments.Count -eq 0) {
            Write-Information '  None found.'
        } elseif (-not $WhatIfPreference) {
            # Deletes are eventually consistent on the ARM side too - confirm they are gone
            # before the deploy re-creates the scope.
            $sweepAttempts = 0
            do {
                Start-Sleep -Seconds 5
                $sweepAttempts++
                $remainingAssignments = @(Get-AzRoleAssignment -Scope $targetSiteScope -ErrorAction SilentlyContinue | Where-Object { $_.Scope -eq $targetSiteScope })
            } while ($remainingAssignments.Count -gt 0 -and $sweepAttempts -lt 12)
            if ($remainingAssignments.Count -gt 0) {
                Write-Warning "Stale role assignment(s) on '$TargetWebAppName' are still listed after $($sweepAttempts * 5)s - the deploy may fail with RoleAssignmentUpdateNotPermitted; re-run if it does."
            } else {
                Write-Information '  Stale role assignments removed.'
            }
        }
    }
}

# ── Deploy cipp ─────────────────────────────────────────────────────────────
$Deployment = $null
if ($SkipDeployment) {
    Write-Information "Skipping ARM deployment — '$($existingCippNgApp.Name)' is already running the container architecture."
} else {
    Write-Information 'Deploying cipp ARM template...'
    if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Deploy cipp ARM template')) {
        # A failed deploy here is an outage (the old apps are gone), so retry transients.
        # FailedIdentityOperation / "pending delete": the reused site name can still have
        # its old managed identity tearing down; clears within a couple of minutes.
        $TransientDeployPattern = 'FailedIdentityOperation|pending delete operation|' + $TransientAzurePattern
        $MaxDeployAttempts = 4
        for ($DeployAttempt = 1; $DeployAttempt -le $MaxDeployAttempts; $DeployAttempt++) {
            try {
                $Deployment = New-AzResourceGroupDeployment -Name 'cipp-migration' @DeploymentParams -Verbose -ErrorAction Stop
                break
            } catch {
                $DeployError = $_.Exception.Message
                if ($DeployAttempt -lt $MaxDeployAttempts -and $DeployError -match $TransientDeployPattern) {
                    $DelaySeconds = 60 * $DeployAttempt
                    Write-Information "Deployment hit a transient error — retrying in ${DelaySeconds}s ($DeployAttempt/$MaxDeployAttempts)... ($($DeployError -split "`n" | Select-Object -First 1))"
                    Start-Sleep -Seconds $DelaySeconds
                    continue
                }
                throw
            }
        }
        Write-Information 'Deployment completed.'
    }
}

# No outputs to read when the deployment was skipped (already migrated) or suppressed (-WhatIf);
# fall back to the existing web app so the DNS summary below still has something to report.
$NewHostname = if ($Deployment) { $Deployment.Outputs['hostname'].Value } elseif ($existingCippNgApp) { $existingCippNgApp.DefaultHostName } else { '' }
$NewWebAppName = if ($Deployment) { $Deployment.Outputs['webAppName'].Value } elseif ($existingCippNgApp) { $existingCippNgApp.Name } else { $TargetWebAppName }
$NewKvName = $existingKv.VaultName

if ($NewHostname) {
    Write-Information "cipp hostname : $NewHostname"
    Write-Information "cipp URL      : https://$NewHostname"
}
Write-Information "Key Vault        : $NewKvName"

# ── Verify the web app identity's grants ─────────────────────────────────────
# The template creates both grants, but the deploy can capture a principal that MSI
# later replaces, and Azure's late cleanup of the deleted function app can remove a
# fresh role assignment. Without Contributor the setup wizard cannot write app
# settings; without the vault policy the backend cannot read its SAM credentials.
# Re-check against the live identity and repair; a brand-new principal is rejected
# for a minute or two while Entra replicates it, hence the retries.
$liveWebApp = if (-not $WhatIfPreference) { Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $NewWebAppName -ErrorAction SilentlyContinue }
$livePrincipalId = $liveWebApp.Identity.PrincipalId
if ($livePrincipalId) {
    Write-Information "Verifying grants for the web app identity ($livePrincipalId)..."
    $siteScope = $liveWebApp.Id
    $grants = @(
        @{
            Name  = "Contributor on '$NewWebAppName'"
            Test  = { [bool](Get-AzRoleAssignment -Scope $siteScope -ObjectId $livePrincipalId -ErrorAction SilentlyContinue | Where-Object { $_.Scope -eq $siteScope -and $_.RoleDefinitionName -eq 'Contributor' }) }
            Grant = { $null = New-AzRoleAssignment -ObjectId $livePrincipalId -RoleDefinitionName Contributor -Scope $siteScope -ObjectType ServicePrincipal -ErrorAction Stop }
            Fix   = "New-AzRoleAssignment -ObjectId $livePrincipalId -RoleDefinitionName Contributor -Scope $siteScope"
        }
        @{
            Name  = "secrets access on Key Vault '$NewKvName'"
            Test  = { [bool]((Get-AzKeyVault -VaultName $NewKvName -ResourceGroupName $ResourceGroupName).AccessPolicies | Where-Object { $_.ObjectId -eq $livePrincipalId -and ($_.PermissionsToSecrets -contains 'all' -or $_.PermissionsToSecrets -contains 'get') }) }
            Grant = { Set-AzKeyVaultAccessPolicy -VaultName $NewKvName -ResourceGroupName $ResourceGroupName -ObjectId $livePrincipalId -PermissionsToSecrets all -ErrorAction Stop }
            Fix   = "Set-AzKeyVaultAccessPolicy -VaultName $NewKvName -ObjectId $livePrincipalId -PermissionsToSecrets all"
        }
    )
    foreach ($grant in $grants) {
        # A Test throw (e.g. Graph 404 on a not-yet-replicated principal) = not verified;
        # fall through to the grant ladder rather than abort post-deploy.
        try { $ok = & $grant.Test } catch { $ok = $false }
        foreach ($delay in @(10, 20, 30, 60, 60)) {
            if ($ok) { break }
            if (-not $PSCmdlet.ShouldProcess($NewWebAppName, "Grant $($grant.Name)")) { break }
            Write-Information "  $($grant.Name) missing - granting..."
            try { & $grant.Grant; $ok = $true } catch {
                if ($_.Exception.Message -match 'already exists') { $ok = $true; break }
                Write-Information "  Failed: $($_.Exception.Message -split "`n" | Select-Object -First 1) - retrying in ${delay}s"
                Start-Sleep -Seconds $delay
            }
        }
        if ($ok) { Write-Information "  $($grant.Name): OK" } else { Write-Warning "Missing $($grant.Name). CIPP will not work until it is granted: $($grant.Fix)" }
    }
} elseif (-not $WhatIfPreference) {
    Write-Warning "Could not read the managed identity of '$NewWebAppName' - verify its Contributor assignment and Key Vault access policy manually."
}

# ── Remove custom domains from SWA before deletion ───────────────────────────
if ($swaCustomDomains.Count -gt 0) {
    Write-Information "Removing custom domains from '$SwaName' before deletion..."
    foreach ($domain in $swaCustomDomains) {
        Write-Information "  Removing custom domain: $($domain.DomainName)"
        if ($PSCmdlet.ShouldProcess($domain.DomainName, 'Remove SWA custom domain')) {
            # Post-deploy: the instance is up, so SWA cleanup failures warn instead of
            # aborting (the summary's DNS instructions must still print).
            try {
                $null = Invoke-AzRestMethodWithRetry `
                    -OperationName "Removing custom domain '$($domain.DomainName)'" `
                    -Method DELETE `
                    -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName/customDomains/$($domain.DomainName)?api-version=2022-09-01"
            } catch {
                Write-Warning "  Failed to remove custom domain '$($domain.DomainName)': $($_.Exception.Message)"
            }
        }
    }

    # Poll until all custom domains are gone (deletion is async)
    Write-Information '  Waiting for custom domain removal to complete...'
    $pollAttempts = 0
    $maxPollAttempts = 24  # 2 minutes at 5s intervals
    do {
        Start-Sleep -Seconds 5
        $remaining = Get-AzStaticWebAppCustomDomain -ResourceGroupName $ResourceGroupName -Name $SwaName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue |
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
if ($swa) {
    Write-Information "Deleting Static Web App '$SwaName'..."
    if ($PSCmdlet.ShouldProcess($SwaName, 'Delete Static Web App')) {
        try {
            $null = Invoke-AzRestMethodWithRetry `
                -OperationName "Deleting Static Web App '$SwaName'" `
                -Method DELETE `
                -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$SwaName`?api-version=2022-09-01"
            Write-Information "  '$SwaName' deleted."
        } catch {
            Write-Warning "Failed to delete Static Web App '$SwaName': $($_.Exception.Message) — delete it in the portal; it no longer serves CIPP."
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Information ''
Write-Information "=== $(if ($SkipDeployment) { 'Cleanup Complete — instance was already migrated, nothing was deployed' } else { 'Migration Complete' }) ==="
Write-Information "CIPP hostname : https://$NewHostname"
Write-Information "Web app name     : $NewWebAppName"
Write-Information "Key Vault        : $NewKvName"
if ($swa) {
    Write-Information "Static Web App '$SwaName' has been deleted."
}

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
        # The alias record is all that's needed — domain-verification TXT records are no longer used.
        Write-Information '  CNAME record'
        Write-Information "    Name  : $domain"
        Write-Information "    Value : $NewHostname"
        Write-Information "  NOTE: if a TXT record named 'asuid.$domain' exists from a previous setup, REMOVE it — these records are no longer used and a leftover one blocks validation."
        Write-Information ''
    }
}
