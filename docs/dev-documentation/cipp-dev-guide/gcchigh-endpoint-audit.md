# GCC High / DoD endpoint routing and bypass audit

This page records how the backend sends a government (GCC High or DoD) direct tenant's API requests to that cloud's hosts, and the audit of code that calls Microsoft hosts without going through the request helpers (redanthrax/CIPP#3). Keep it in step with `backend/Tests/Static/CommercialHostBypass.Tests.ps1`, which fails when a new direct call appears.

## How routing works

* **The map.** `Get-CIPPCloudEndpoint` holds every host as a literal, per cloud (`Commercial`, `USGovHigh`, `USGovDoD`, matched exactly and case-sensitively). Nothing builds a host from a stored value, a discovery document or request input. An unknown, empty or miscased cloud throws.
* **The decision.** `Resolve-CIPPCloudHost` maps a host for a cloud. Commercial: unchanged. Government: a commercial service host becomes that cloud's host for the same service; a host of that cloud, or a SharePoint host under its suffix, is kept; anything else throws `... is not supported for government tenants`.
* **Requests.** `ConvertTo-CIPPCloudUri` parses the URI with `[uri]`, requires an absolute `https` URI with a bare host (no user info, no port other than 443) and replaces only the host. Path, query and fragment are kept byte for byte.
* **Tokens.** `ConvertTo-CIPPCloudScope` uses the same decision for token resources, so a token is only requested from the government authority for a government resource (`Get-GraphToken`, #2).
* **The tenant's cloud.** `Get-CIPPTenantRequestCloud` reads the cloud marker `Get-GraphToken` already keeps in the shared token cache (`CIPP.CIPPTokenCache`, 15 minutes). On a miss it reads the Tenants table with the same rule as `Get-GraphToken` (a direct tenant's `cloudEnvironment`, else `CIPP_PARTNER_CLOUD`) and stores the marker. The host and the token for a request therefore always follow the same marker.

### Hosts

| Service | Commercial | USGovHigh | USGovDoD | Source | Confidence |
| --- | --- | --- | --- | --- | --- |
| Sign-in | `login.microsoftonline.com` | `login.microsoftonline.us` | `login.microsoftonline.us` | [Graph national clouds](https://learn.microsoft.com/graph/deployments) | High |
| Microsoft Graph | `graph.microsoft.com` | `graph.microsoft.us` | `dod-graph.microsoft.us` | [Graph national clouds](https://learn.microsoft.com/graph/deployments) | High (live-testable) |
| Exchange Online (admin API) | `outlook.office365.com` | `outlook.office365.us` | `webmail.apps.mil` | [Connect-ExchangeOnline, ConnectionUri](https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline) | Host high; token resource (`https://<host>`) medium, DoD lower - not documented as a resource |
| Office 365 Management API | `manage.office.com` | `manage.office365.us` | `manage.protection.apps.mil` | [Management Activity API reference](https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference) | Host high; token resource medium |
| Defender for Endpoint API | `api.securitycenter.microsoft.com` (also `api.securitycenter.windows.com`) | `api-gov.securitycenter.microsoft.us` | `api-gov.securitycenter.microsoft.us` | [Defender for Endpoint for US Government](https://learn.microsoft.com/defender-endpoint/gov) | Host high; token resource medium |
| SharePoint (suffix) | `*.sharepoint.com` | `*.sharepoint.us` | `*.sharepoint-mil.us` | [GCC High endpoints](https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-u-s-government-gcc-high-endpoints), [DoD endpoints](https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-u-s-government-dod-endpoints) | High |

A wrong token resource fails at the government authority (`AADSTS500011`); it never sends anything to a commercial host.

**Not supported for government tenants** (throws before any token or request): Teams admin ConfigAPI (`api.interfaces.records.teams.microsoft.com` - no documented government host), Security & Compliance PowerShell (`ps.compliance.protection.outlook.com` - its redirect discovery builds commercial host names), Partner Center, `admin.microsoft.com`, `licensing.m365.microsoft.com`, `reports.office.com`, `substrate.office.com`, `outlook.office.com`, the MFA push connector, and any GUID-form token resource.

**Graph paths Azure Government does not have.** These reach `graph.microsoft.us` and fail there; they are not refused by the helpers but are gated by the feature support matrix ([feature support](gcchigh-feature-support.md), #4). Live results for a GCC High tenant on 2026-11-11:

| Path | Result | CIPP |
| --- | --- | --- |
| `beta/copilot/admin/settings`, `beta/copilot/admin/policySettings/...` | 400 Resource not found for the segment 'admin' | Gated (`copilot-admin`) |
| `beta/copilot/admin/catalog/packages` | 400 Resource not found for the segment 'admin' | Gated (`copilot-admin`) |
| `beta/reports/getOneDriveUsageAccountDetail`, `getTeamsUserActivityUserDetail`, `getMailboxUsageDetail` | 200 | Supported; CIPP calls these |
| `v1.0/reports/...` usage reports | 400 Resource not found for the segment | Not called by CIPP |
| Users filtered or written with the partner's `ext..._cippUser` schema extension | 500 Resource does not exist | JIT Admin refused (`Get-CIPPJITAdminCloudError`) |

### Helpers

| Helper | Government behaviour |
| --- | --- |
| `New-GraphGetRequest` | Host rewritten; every page (including each `@odata.nextLink`) is checked, so paging stays on the tenant's cloud. Also routes the Exchange REST URIs callers send through it with `-scope ExchangeOnline`. |
| `New-GraphPOSTRequest` (and `New-CIPPGraphRetry`, which calls it) | Host rewritten. |
| `New-GraphBulkRequest` | `$batch` URL rewritten; government `nextLink`s are stripped to relative URLs for re-batching. Sub-request URLs are relative to the batch host. |
| `New-GraphMultiTenantBulkRequest` | Each tenant's `$batch` URL follows that tenant's cloud; a routing error becomes that tenant's `Error`. |
| `New-ExoRequest`, `New-ExoBulkRequest` | Exchange host rewritten; each `@odata.nextLink` `New-ExoRequest` follows is checked the same way; `-Compliance` refused. |
| `New-TeamsRequestV2` | Refused before a token is requested. |
| `Get-ClassicAPIToken` / `New-ClassicAPIGetRequest` | Refused before the commercial token endpoint. |
| `New-CIPPMFAConnectorToken` | Refused before the MFA service principal secret is created or sent, and checked again just before the secret is sent (the first check reads a marker that can be stale in this worker). |

Commercial tenants: one in-memory dictionary lookup per helper call (the marker; a table read at most once per 15 minutes per tenant and worker), then a string compare. Their URIs are passed on unchanged.

## Bypass audit

Files that make their own HTTP call (`Invoke-RestMethod`, `Invoke-WebRequest`, `Invoke-CIPPRestMethod`, `CIPPRestClient`, `HttpClient`) and name a commercial Microsoft host. 36 files:

| Disposition | Count |
| --- | --- |
| Request helper, routes by cloud | 6 |
| Helper or token path that refuses government tenants | 4 |
| Token acquisition, government authority (#2) | 2 |
| Fixed in place | 1 |
| Fails closed through a helper it calls | 1 |
| Microsoft API calls already go through the helpers; the direct call goes elsewhere | 7 |
| Anonymous public lookup, no token or tenant data | 4 |
| Partner tenant only (commercial by design) | 6 |
| CIPP's own Azure resources | 5 |

Paths are under `backend/Modules/`.

| File | Host(s) | What it does | Disposition |
| --- | --- | --- | --- |
| `CIPPCore/Public/GraphHelper/New-GraphGetRequest.ps1` | graph, outlook.office365.com | Graph GET helper | Routes by cloud |
| `CIPPCore/Public/GraphHelper/New-GraphPOSTRequest.ps1` | graph | Graph write helper | Routes by cloud |
| `CIPPCore/Public/GraphHelper/New-GraphBulkRequest.ps1` | graph | Graph `$batch` helper | Routes by cloud |
| `CIPPCore/Public/GraphHelper/New-GraphMultiTenantBulkRequest.ps1` | graph | Graph `$batch` across tenants | Routes by cloud, per tenant |
| `CIPPCore/Public/GraphHelper/New-ExoRequest.ps1` | outlook.office365.com, ps.compliance.protection.outlook.com | Exchange admin API | Routes by cloud; compliance refused |
| `CIPPCore/Public/GraphHelper/New-ExoBulkRequest.ps1` | outlook.office365.com, ps.compliance.protection.outlook.com | Exchange admin API `$batch` | Routes by cloud; compliance refused |
| `CIPPCore/Public/GraphHelper/New-TeamsRequestV2.ps1` | api.interfaces.records.teams.microsoft.com | Teams admin ConfigAPI | Refuses government tenants |
| `CIPPCore/Public/GraphHelper/Get-ClassicAPIToken.ps1` | login.microsoftonline.com | v1 token for classic admin APIs | Refuses government tenants |
| `CIPPCore/Public/GraphHelper/New-ClassicAPIGetRequest.ps1` | admin.microsoft.com | Classic admin API GET | Refused via `Get-ClassicAPIToken` |
| `CIPPCore/Public/GraphHelper/New-CIPPMFAConnectorToken.ps1` | login.microsoftonline.com, adnotifications.windowsazure.com | Token for the MFA push connector | Refuses government tenants |
| `CIPPCore/Public/GraphHelper/Get-GraphToken.ps1` | login.microsoftonline.com, graph | Token acquisition | Government authority, app and scope (#2) |
| `CIPPCore/Public/GraphHelper/Get-GraphTokenFromCert.ps1` | login.microsoftonline.com, graph | Certificate token acquisition | Government authority (#2) |
| `CIPPHTTP/.../CIPP/Core/Invoke-ExecGraphRequestProfile.ps1` | graph | Diagnostic: times direct Graph calls with a tenant's token | **Fixed in place**: the URL is routed by cloud before the direct calls |
| `CIPPHTTP/.../Identity/Administration/Users/Invoke-ExecSendPush.ps1` | strongauthenticationservice.auth.microsoft.com, adnotifications.windowsazure.com | MFA push to a user | Fails closed: `New-CIPPMFAConnectorToken` refuses government tenants first |
| `CIPPCore/Public/Add-CIPPWin32LobAppContent.ps1` | graph | Win32 app upload | Graph via helpers; direct PUTs go to the storage SAS URL Graph returned (the tenant's cloud) |
| `CIPPBaselines/Public/Executors/Invoke-CIPPBaselineGlobalSecureAccessCompliantNetwork.ps1` | graph | Global Secure Access baseline | Graph via helpers; `Invoke-WebRequest` is inside the script deployed to devices |
| `CippExtensions/Public/HIBP/Get-BreachInfo.ps1` | graph | Breach lookup | Graph via helper; direct call to a third party |
| `CippExtensions/Public/NinjaOne/Invoke-NinjaOneDeviceWebhook.ps1` | graph | NinjaOne webhook | Graph via helper; direct calls to NinjaOne |
| `CippExtensions/Public/NinjaOne/Invoke-NinjaOneTenantSync.ps1` | graph, portal links | NinjaOne sync | Graph via helpers; direct calls to NinjaOne; Microsoft hosts are UI links only (commercial portals - see below) |
| `CIPPHTTP/.../Teams-Sharepoint/Invoke-ExecReactivateSite.ps1` | graph | Site unarchive | Graph via helpers (`Invoke-CIPPRestMethod` appears in a comment only) |
| `CIPPCore/Public/GraphHelper/Get-SharePointAdminLink.ps1` | graph, autodiscover-s.outlook.com, sharepoint.com | SharePoint URLs | Graph via helper (returns the tenant's `.us` / `-mil.us` hosts); `-Public` autodiscover is anonymous and unused by callers |
| `CIPPCore/Public/GraphHelper/Get-CIPPTenantCloudEnvironment.ps1` | login.microsoftonline.com | OpenID discovery to detect a tenant's cloud | Anonymous; the commercial discovery endpoint answers for every cloud |
| `CIPPCore/Public/Get-TenantIdFromSubscriptionId.ps1` | management.azure.com | Tenant id from a subscription id | Anonymous |
| `CIPPCore/Public/BEC/Get-CIPPMicrosoft365IPRanges.ps1` | endpoints.office.com | Public IP range list | Anonymous public data |
| `CIPPHTTP/.../Tenant/Administration/Tenant/Invoke-ListExternalTenantInfo.ps1` | login.windows.net, login.microsoftonline.com, graph | External tenant lookup | Anonymous lookups; Graph via helper as the partner tenant |
| `CIPPCore/Public/Send-CIPPAlert.ps1` | graph | Alert e-mail and webhooks | Partner tenant only |
| `CIPPCore/Public/Get-CIPPAuthentication.ps1` | login.microsoftonline.com | Resolves the partner tenant id | Partner tenant only (anonymous) |
| `CIPPCore/Public/Get-CIPPPartnerAzSubscriptions.ps1` | api.partnercenter.microsoft.com, login.windows.net | CSP Azure subscriptions | Partner Center with the partner token; no government customers (GDAP does not cross clouds) |
| `CIPPCore/Public/Authentication/Test-CIPPSAMSecret.ps1` | login.microsoftonline.com, graph | Tests the SAM app secret | Partner tenant only |
| `CIPPHTTP/.../CIPP/Setup/Invoke-ExecCreateSAMApp.ps1` | graph | Creates CIPP-SAM | Partner setup with the partner admin's token |
| `CIPPCore/Public/GraphHelper/New-DeviceLogin.ps1` | login.microsoftonline.com | Device-code sign-in | Partner setup |
| `CIPPCore/Public/GraphHelper/New-CIPPAzRestRequest.ps1` | management.azure.com, storage.azure.com | ARM / storage via managed identity | CIPP's own Azure resources |
| `CIPPCore/Public/Authentication/Get-CIPPAzIdentityToken.ps1` | management.azure.com, storage.azure.com | Managed identity token | CIPP's own Azure resources |
| `CIPPCore/Public/Authentication/Remove-CIPPMigrationAppSetting.ps1` | management.azure.com | App setting clean-up | CIPP's own Azure resources |
| `CIPPCore/Public/Authentication/Set-CIPPSSOEasyAuth.ps1` | login.microsoftonline.com, management.azure.com | Easy Auth setup | CIPP's own Azure resources |
| `CIPPHTTP/.../CIPP/Settings/Invoke-ExecContainerManagement.ps1` | management.azure.com | Container management | CIPP's own Azure resources |

`CIPPHTTP/...` is `CIPPHTTP/Public/Entrypoints/HTTP Functions/...`.

### Hosts called through the helpers

Code that calls a non-Graph host through `New-GraphGetRequest` / `New-GraphPOSTRequest` gets the same routing: supported hosts move to the tenant's cloud, the rest throw for a government tenant. Counted from literal `-uri` arguments:

| Host | Calls | Government behaviour |
| --- | --- | --- |
| `graph.microsoft.com` | ~1,250 | Routed |
| `outlook.office365.com` | 6 | Routed (Exchange REST, `-scope ExchangeOnline`) |
| `manage.office.com` | 3 | Routed (audit log subscriptions and content) |
| `api.securitycenter.microsoft.com` | 3 | Routed (MDE offboarding, TVM export) |
| SharePoint admin / root URLs (built from `Get-SharePointAdminLink`) | many | Routed when they are on the tenant's suffix |
| `api.partnercenter.microsoft.com` | 14 | Throws (Partner Center is partner-only; these use the partner token) |
| `admin.microsoft.com` | 14 | Throws |
| `licensing.m365.microsoft.com` | 5 | Throws |
| `reports.office.com` | 2 | Throws |
| `substrate.office.com` | 1 | Throws |
| `mde-rsp-apiportal-prd-*.securitycenter.windows.com` (`Enable-CIPPMDEConnector`) | 1 | Throws (no documented government equivalent) |

### Fixed outside the helpers

* `Invoke-ExecGraphRequestProfile` - routes its direct calls by cloud (above).
* `Invoke-ExecAddTenant` - clears the tenant's cached tokens and cloud marker after writing a new direct tenant, so a marker cached before the row existed cannot route it to the partner cloud for 15 minutes.
* `Get-GraphRequestList` - manual pagination accepted only a `graph.microsoft.com` nextLink, so page 2 of any list failed for a government tenant. It now accepts the Graph host of the tenant's own cloud and nothing else.
* `Get-GraphToken`, `Get-CIPPTenantRequestCloud` - trim the tenant id before the Tenants lookup, as the cache key already does. Before, `' <id>'` shared a government tenant's cache keys and cloud marker while missing its row, so it could overwrite the marker with the partner cloud.
* `Get-GraphToken`, `Get-CIPPTenantRequestCloud` - also find a government direct tenant by its `initialDomainName` (for example `contoso.onmicrosoft.us`), with the same rule in both: only when no row matched by id or `defaultDomainName`, and only a row whose `cloudEnvironment` is set and not `Commercial`. Before, such a tenant fell to the partner's commercial credentials (AADSTS900382). Commercial and GDAP lookups are unchanged.
* `Get-GraphToken` - refreshes the cloud marker on `-SkipCache` requests too. Before, a `-SkipCache` token (CPV refresh, `Add-CIPPApplicationPermission`, ...) read the tenant's current cloud from the table while the request helpers could still follow a stale marker, pairing a government token with `graph.microsoft.com`.

## Known limits

* **The guard is per file.** It cannot follow a host held in a variable built in another file. It catches new direct calls in the usual form.
* **A tenant addressed by an alias** that is neither its id, its `defaultDomainName` nor (for a government direct tenant) its `initialDomainName` is treated as the partner cloud by both `Get-GraphToken` and the request helpers (they agree, so a government tenant addressed this way fails at the commercial authority rather than leaking anything).
* **Cloud changes across workers.** `Invoke-EditTenantCloudEnvironment` (and a re-add) clears the token cache and marker in its own worker only; other workers follow the old marker for up to 15 minutes, consistently on the old cloud. Each worker also keeps a `seen` entry (`<tenant>|cipp-cloud-environment|delegated||seen`, 24 h, refreshed on use) naming the government cloud it last routed the tenant to. When `Get-GraphToken`'s slow path or `Get-CIPPTenantRequestCloud`'s table read finds the tenant in a government cloud the entry does not name, it drops all of that tenant's cached tokens first (`RemoveByTenant`), so a commercial token cached before the change cannot outlive it. Minting a commercial token removes the entry. Commercial tenants never reach the drop, and the fast path is unchanged. The request helpers (`New-GraphGetRequest`, `New-GraphPOSTRequest`, `New-GraphBulkRequest` and its retries, `New-GraphMultiTenantBulkRequest`, `New-ExoRequest`, `New-ExoBulkRequest`, and `Invoke-ExecGraphRequestProfile`) fetch the token before choosing the host, so for a government cloud they fetch it again with `Get-GraphToken -RequireCloud <cloud>`: that call never reads the commercial cache key, returns only a token minted for that cloud, and throws (nothing sent) if the table now gives another cloud. So the request that first reads the new cloud cannot carry the cached commercial token to the government host. Commercial requests never pass `-RequireCloud` and make the same single token call as before; a government request makes a second call that is answered from the cache (two in-memory lookups), except with `-skipTokenCache`, where it mints a second token. Caller-supplied `-Headers` are used as given. Bumping the credential version (`Set-CIPPCredentialVersion`) does not help here: other workers read it only on the token slow path, after the fast path has already returned the cached token, and it reloads credentials without clearing the token cache.
* **Commercial <-> government for a direct tenant** is refused by `Invoke-EditTenantCloudEnvironment` (400) in both directions: the tenant's stored refresh token was issued by the authority of the cloud it was added in (`login.microsoftonline.com` or `login.microsoftonline.us`) and would otherwise be sent to the other one. Remove and re-add the tenant instead. USGovHigh <-> USGovDoD share `login.microsoftonline.us` and stays allowed; non-direct tenants are unaffected. The mismatch messages in `Invoke-ExecAddTenant` and `Invoke-ExecUpdateRefreshToken` suggest changing the stored cloud only between GCC High and DoD, and a remove and re-add otherwise.
* **String handling of Graph URLs in callers** (for example `New-CIPPBackupTask` stripping `https://graph.microsoft.com/beta/deviceManagement/` to name backups, `Get-AuthorisedRequest`'s partner-endpoint patterns) is cosmetic or partner-only and was left as is.
* **Portal links** are re-pointed for government tenants (#4): see "Portal links" in `gcchigh-feature-support.md`. Links about the partner's own tenant (CIPP-SAM in `portal.azure.com`, GDAP invitations in `admin.microsoft.com`) and the per-row links of an AllTenants view are left as they are.
