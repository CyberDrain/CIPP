# Guard for redanthrax/CIPP#3: requests for a government (GCC High / DoD) tenant must go through
# the request helpers, which route them to the tenant's cloud. A file that makes its own HTTP
# call (Invoke-RestMethod, Invoke-WebRequest, Invoke-CIPPRestMethod, CIPPRestClient, HttpClient)
# AND names a commercial Microsoft API host can send a government tenant's token or data to a
# commercial host, so every such file has been reviewed and is listed below with what it does.
#
# This test fails when:
#   - a new file makes a direct call and names a commercial Microsoft host. Route the call through
#     New-GraphGetRequest / New-GraphPOSTRequest / New-GraphBulkRequest / New-ExoRequest (which
#     route by cloud), or make it fail closed for government tenants
#     (Get-CIPPTenantRequestCloud), then add it here and to docs/dev-documentation/cipp-dev-guide/gcchigh-endpoint-audit.md.
#   - a listed file no longer matches (the entry is stale): remove it here and in the audit.
#
# The check is per file, not per call: it cannot follow a host held in a variable built in
# another file. It is a tripwire for new code, not a proof.

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

    # Reviewed files (redanthrax/CIPP#3). Keep in step with docs/dev-documentation/cipp-dev-guide/gcchigh-endpoint-audit.md.
    $script:Reviewed = [ordered]@{
        # The request and token helpers themselves: they route by cloud or refuse government tenants.
        'CIPPCore/Public/GraphHelper/New-GraphGetRequest.ps1'                                                   = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-GraphPOSTRequest.ps1'                                                  = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-GraphBulkRequest.ps1'                                                  = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-GraphMultiTenantBulkRequest.ps1'                                       = 'helper: routes by cloud'
        'CIPPCore/Public/GraphHelper/New-ExoRequest.ps1'                                                        = 'helper: routes by cloud; compliance refused for government'
        'CIPPCore/Public/GraphHelper/New-ExoBulkRequest.ps1'                                                    = 'helper: routes by cloud; compliance refused for government'
        'CIPPCore/Public/GraphHelper/New-TeamsRequestV2.ps1'                                                    = 'helper: refuses government tenants'
        'CIPPCore/Public/GraphHelper/Get-GraphToken.ps1'                                                        = 'token: government authority and app (#2)'
        'CIPPCore/Public/GraphHelper/Get-GraphTokenFromCert.ps1'                                                = 'token: government authority (#2)'
        'CIPPCore/Public/GraphHelper/Get-ClassicAPIToken.ps1'                                                   = 'token: refuses government tenants'
        'CIPPCore/Public/GraphHelper/New-ClassicAPIGetRequest.ps1'                                              = 'helper: refused via Get-ClassicAPIToken'
        'CIPPCore/Public/GraphHelper/New-CIPPMFAConnectorToken.ps1'                                             = 'refuses government tenants'
        'CIPPCore/Public/GraphHelper/Get-SharePointAdminLink.ps1'                                               = 'Graph via helper; -Public autodiscover is anonymous'
        'CIPPCore/Public/GraphHelper/Get-CIPPTenantCloudEnvironment.ps1'                                        = 'anonymous OpenID discovery (answers for every cloud)'
        'CIPPCore/Public/GraphHelper/New-DeviceLogin.ps1'                                                       = 'partner setup: device code sign-in'
        'CIPPCore/Public/GraphHelper/New-CIPPAzRestRequest.ps1'                                                 = 'CIPP''s own Azure resources'
        # Fixed in place or safe for government tenants.
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecGraphRequestProfile.ps1'               = 'fixed: routes the direct calls by cloud'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecSendPush.ps1'      = 'refused via New-CIPPMFAConnectorToken'
        'CIPPCore/Public/Add-CIPPWin32LobAppContent.ps1'                                                        = 'Graph via helper; upload to the SAS URL Graph returns'
        'CIPPBaselines/Public/Executors/Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork.ps1'              = 'Graph via helper; Invoke-WebRequest is in the device script'
        'CippExtensions/Public/HIBP/Get-BreachInfo.ps1'                                                         = 'Graph via helper; direct call is to a third party'
        'CippExtensions/Public/NinjaOne/Invoke-NinjaOneDeviceWebhook.ps1'                                       = 'Graph via helper; direct calls are to NinjaOne'
        'CippExtensions/Public/NinjaOne/Invoke-NinjaOneTenantSync.ps1'                                          = 'Graph via helper; direct calls are to NinjaOne; portal links only'
        'CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecReactivateSite.ps1'             = 'Graph via helper; Invoke-CIPPRestMethod named in a comment'
        # Partner tenant or CIPP's own infrastructure only: never called with a direct tenant's token.
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

Describe 'Direct calls to commercial Microsoft hosts (redanthrax/CIPP#3)' {
    It 'finds the files it is meant to check' -TestCases @(@{ Found = $script:Found }) {
        param($Found)
        $Found | Should -Contain 'CIPPCore/Public/GraphHelper/New-GraphGetRequest.ps1'
    }

    # One assertion per list rather than -ForEach: an empty -ForEach fails the container under Pester 6
    # (Run.FailOnNullOrEmptyForEach), and one of the two lists is empty in every state.
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
