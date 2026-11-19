# Pester tests for direct calls to commercial Microsoft hosts.

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $RepoRoot 'Modules'

    $DirectCall = '(?i)\b(Invoke-RestMethod|Invoke-WebRequest|Invoke-CIPPRestMethod|irm|iwr)\b|CIPPRestClient\]::|CIPPConcurrentRequest|\bHttpClient\b|\bWebClient\b'
    $CommercialHost = '(?i)https://(?:[a-z0-9-]+\.)*(?:graph\.microsoft\.com|graph\.windows\.net|login\.microsoftonline\.com|login\.windows\.net|login\.microsoft\.com|outlook\.office365\.com|outlook\.office\.com|outlook\.com|manage\.office\.com|securitycenter\.(?:microsoft|windows)\.com|security\.microsoft\.com|teams\.microsoft\.com|sharepoint\.com|partnercenter\.microsoft\.com|admin\.microsoft\.com|office\.com|auth\.microsoft\.com|windowsazure\.com|azure\.com)\b'

    $script:Found = @(Get-ChildItem -Path $ModulesRoot -Recurse -Filter '*.ps1' -File | ForEach-Object {
            $Text = Get-Content -Raw -LiteralPath $_.FullName
            if ($Text -match $DirectCall -and $Text -match $CommercialHost) {
                $_.FullName.Substring($ModulesRoot.Length + 1).Replace('\', '/')
            }
        } | Sort-Object)

    # Keep in step with docs/dev-documentation/cipp-dev-guide/gcchigh-endpoint-audit.md.
    $script:Reviewed = [ordered]@{
        'CIPPCore/Public/GraphHelper/New-GraphGetRequest.ps1'                                                   = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-GraphPOSTRequest.ps1'                                                  = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-GraphBulkRequest.ps1'                                                  = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-GraphMultiTenantBulkRequest.ps1'                                       = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-ExoRequest.ps1'                                                        = 'helper: routes by cloud; compliance refused for government'
        'CIPPCore/Public/GraphHelper/New-ExoBulkRequest.ps1'                                                    = 'helper: routes by cloud; compliance refused for government'
        'CIPPCore/Public/GraphHelper/New-TeamsRequestV2.ps1'                                                    = 'helper: refuses government tenants'
        'CIPPCore/Public/GraphHelper/Get-GraphToken.ps1'                                                        = 'token: government authority and app'
        'CIPPCore/Public/GraphHelper/Get-GraphTokenFromCert.ps1'                                                = 'token: government authority'
        'CIPPCore/Public/GraphHelper/Get-ClassicAPIToken.ps1'                                                   = 'token: refuses government tenants'
        'CIPPCore/Public/GraphHelper/New-ClassicAPIGetRequest.ps1'                                              = 'helper: refused via Get-ClassicAPIToken'
        'CIPPCore/Public/GraphHelper/New-CIPPMFAConnectorToken.ps1'                                             = 'refuses government tenants'
        'CIPPCore/Public/GraphHelper/Get-SharePointAdminLink.ps1'                                               = 'Graph via helper; -Public autodiscover is anonymous'
        'CIPPCore/Public/GraphHelper/Get-CIPPTenantCloudEnvironment.ps1'                                        = 'anonymous OpenID discovery (answers for every cloud)'
        'CIPPCore/Public/GraphHelper/New-DeviceLogin.ps1'                                                       = 'partner setup: device code sign-in'
        'CIPPCore/Public/GraphHelper/New-CIPPAzRestRequest.ps1'                                                 = 'CIPP''s own Azure resources'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecGraphRequestProfile.ps1'               = 'fixed: routes the direct calls by cloud'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecSendPush.ps1'      = 'refused via New-CIPPMFAConnectorToken'
        'CIPPCore/Public/Add-CIPPWin32LobAppContent.ps1'                                                        = 'Graph via helper; upload to the SAS URL Graph returns'
        'CIPPBaselines/Public/Executors/Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork.ps1'              = 'Graph via helper; Invoke-WebRequest is in the device script'
        'CippExtensions/Public/HIBP/Get-BreachInfo.ps1'                                                         = 'Graph via helper; direct call is to a third party'
        'CippExtensions/Public/NinjaOne/Invoke-NinjaOneDeviceWebhook.ps1'                                       = 'Graph via helper; direct calls are to NinjaOne'
        'CippExtensions/Public/NinjaOne/Invoke-NinjaOneTenantSync.ps1'                                          = 'Graph via helper; direct calls are to NinjaOne; portal links only'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecReactivateSite.ps1'             = 'Graph via helper; Invoke-CIPPRestMethod named in a comment'
        'CIPPCore/Public/Send-CIPPAlert.ps1'                                                                    = 'partner tenant mail; webhooks'
        'CIPPCore/Public/Get-CIPPAuthentication.ps1'                                                            = 'partner tenant id lookup (anonymous)'
        'CIPPCore/Public/Get-CIPPPartnerAzSubscriptions.ps1'                                                    = 'Partner Center (partner token)'
        'CIPPCore/Public/Get-TenantIdFromSubscriptionId.ps1'                                                    = 'anonymous ARM lookup'
        'CIPPCore/Public/BEC/Get-CIPPMicrosoft365IPRanges.ps1'                                                  = 'public endpoint list'
        'CIPPCore/Public/Authentication/Test-CIPPSAMSecret.ps1'                                                 = 'partner SAM app secret test'
        'CIPPCore/Public/Authentication/Get-CIPPAzIdentityToken.ps1'                                            = 'CIPP''s own managed identity'
        'CIPPCore/Public/Authentication/Remove-CIPPMigrationAppSetting.ps1'                                     = 'CIPP''s own Azure resources'
        'CIPPCore/Public/Authentication/Set-CIPPSSOEasyAuth.ps1'                                                = 'CIPP''s own Azure resources'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecContainerManagement.ps1'           = 'CIPP''s own Azure resources'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Setup/Invoke-ExecCreateSAMApp.ps1'                     = 'partner setup with the partner admin''s token'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Tenant/Invoke-ListExternalTenantInfo.ps1' = 'anonymous lookups; Graph via helper as the partner'
    }
    $script:New = @($script:Found | Where-Object { -not $script:Reviewed.Contains($_) })
    $script:Stale = @($script:Reviewed.Keys | Where-Object { $_ -notin $script:Found })
}

Describe 'Direct calls to commercial Microsoft hosts' {
    It 'finds the files it is meant to check' -TestCases @(@{ Found = $script:Found }) {
        param($Found)
        $Found | Should -Contain 'CIPPCore/Public/GraphHelper/New-GraphGetRequest.ps1'
    }

    # Not -ForEach: Pester 6 fails an empty -ForEach (Run.FailOnNullOrEmptyForEach), and one list is always empty.
    It 'has no unreviewed file calling a commercial Microsoft host directly' -TestCases @(@{ New = $script:New }) {
        param($New)
        if ($New) {
            throw "$($New -join ', ') make(s) a direct HTTP call and name(s) a commercial Microsoft host. Route it through the request helpers (they send government tenants to their cloud) or make it fail closed for government tenants, then list it in Tests/Static/CommercialHostBypass.Tests.ps1 and docs/dev-documentation/cipp-dev-guide/gcchigh-endpoint-audit.md."
        }
    }

    It 'has no stale reviewed entry' -TestCases @(@{ Stale = $script:Stale }) {
        param($Stale)
        if ($Stale) {
            throw "$($Stale -join ', ') is listed as reviewed but no longer matches (moved, renamed or fixed). Remove it from the list and the audit."
        }
    }
}
