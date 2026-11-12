# GCC High / DoD feature support

Some CIPP features call services that a government (GCC High or DoD) tenant cannot use. The request helpers refuse those calls for a government tenant before anything is sent ([endpoint routing](gcchigh-endpoint-audit.md), redanthrax/CIPP#3). This page describes how CIPP hides or skips those features so that the refusals do not show up as failing pages and repeated errors (redanthrax/CIPP#4).

None of this changes anything for a Commercial tenant. Every check returns early for Commercial, for AllTenants and when the tenant's cloud is unknown.

## The support matrix

The matrix lives in one file, `frontend/src/data/cloudFeatureSupport.json`. The backend reads an identical copy at `backend/Config/cloudFeatureSupport.json`. Edit the frontend copy and copy it over the backend one. `backend/Tests/Static/CloudFeatureSupportSync.Tests.ps1` fails if the copies differ.

Each section lists features by key, with the clouds they are unsupported in and a `source`:

| Section | Key | Used by |
| --- | --- | --- |
| `pages` | page path (also covers the pages under it, unless the entry has `"exact": true`; `navFallback` names a supported page the nav item opens instead) | Navigation, tabs, direct URL block |
| `actions` | API URL of a row/header action | `CippDataTable`, `HeaderedTabbedLayout` |
| `standards` | classic standard name | `Push-CIPPStandardsList`, `Push-CIPPStandard`, standards picker |
| `baselineStandards` | baseline definition name | `Invoke-CIPPBaselineStandard`, baseline picker |
| `alerts` | alert name (`Get-CIPPAlert<name>`) | `Push-ExecScheduledCommand` |
| `tests` | test id (`Invoke-CippTest<id>`) | `Invoke-CIPPTestCollection` |
| `cacheTypes` | cache type (`Set-CIPPDBCache<type>`) | `Invoke-CIPPDBCacheCollection`, `Push-ExecCIPPDBCache` |
| `timers` | timer step | `Start-AuditLogSearchCreationV2` |

`sources` gives each source's reason and evidence: a refusal from #3, a Microsoft Graph page whose national cloud table says "global only", or a live call against a GCC High tenant on `graph.microsoft.us` that failed because the API is not there. Only features backed by a refusal, a document or a live failure are listed. A feature that only needs a licence is not listed, because `Test-CIPPStandardLicense` and the tenant capabilities already handle licences. Features that might be unsupported but are not proven are listed under `unverified` and are not gated.

`baselineStandards` and `tests` are derived lists. A baseline standard is listed when its executor, a `"compliance": true` step, a `GraphRequest` step that calls `copilot/admin/` or its `read.cacheType` is unsupported. A test is listed when every cache type it reads is unsupported. The static test re-derives both lists and fails when a new definition is not in the matrix. It also fails when a classic standard or cache type that calls `copilot/admin/` is not listed.

### What is gated

| Source | Pages | Background work |
| --- | --- | --- |
| `teams-configapi` | Business Voice | Teams standards, baselines, CIS 8.x tests, Teams cache types |
| `security-compliance` | DLP, retention, labels, sensitive info types | Purview standards and baselines, CIS 3.2.x, CopilotReady014, ORCA242, compliance cache types |
| `m365-licensing`, `mde-connector`, `mfa-connector`, `reports-office`, `audit-log-query`, `managed-tenants` | Graph/Office reports | Self-service licences, pending licence requests alert, Defender compliance policy, MFA push action, Copilot readiness cache, audit log planner, Defender alerts |
| `copilot-usage-reports` | Copilot adoption, trend, usage | CopilotReady015-017, Copilot usage cache types |
| `copilot-admin` | Copilot Settings, Agent 365 Packages | CopilotSettings and CopilotLimitedMode standards and baselines, CopilotAdminSettings and CopilotPolicySettings cache types |
| `global-secure-access` | Global Secure Access (filtering policies, security profiles, traffic forwarding) | Global Secure Access baselines, NetworkAccess and NetworkAccessFiltering cache types |
| `cipp-schema-extension` | JIT Admins (exact: the template, role template, request and add pages stay; the JIT Admin nav item opens Requests and the JIT Admins tab is hidden) | JIT Admin endpoints, see below |

`global-secure-access`: Microsoft's [known limitations](https://learn.microsoft.com/entra/global-secure-access/reference-current-known-limitations) page says Global Secure Access is available in GCC but "isn't yet supported in the US Government Community Cloud High (GCC-H), Department of Defense cloud" (read 2026-11-11). Upstream added the Global Secure Access pages and most of its baselines; the existing Compliant Network baseline reads the same cache type and is gated with them.

`copilot-admin`: on 2026-11-11 `beta/copilot/admin/settings` (all five settings on the Copilot Settings page) and `beta/copilot/admin/catalog/packages` returned 400 "Resource not found for the segment 'admin'" from `graph.microsoft.us` for a GCC High tenant. DoD is listed with it because Microsoft 365 Copilot is not offered there either.

### Verified supported

Microsoft 365 usage reports are not gated. On 2026-11-11, with `Reports.Read.All` consented, `beta/reports/getOneDriveUsageAccountDetail`, `getTeamsUserActivityUserDetail` and `getMailboxUsageDetail` returned 200 from `graph.microsoft.us` for a GCC High tenant. The v1.0 versions returned 400 "Resource not found for the segment", which matches Microsoft's v1.0 pages (global only), but CIPP calls the beta versions: the bulk helpers and `ListGraphRequest` default to beta and no CIPP code calls a v1.0 usage report. (The Graph Explorer presets let the user pick v1.0 by hand.)

## Frontend

* **Selected tenant's cloud.** `useTenantCloudEnvironment()` reads `cloudEnvironment` from the tenant list the tenant selector already cached (query key `TenantSelector`). It reads the query cache directly (`useSyncExternalStore` on the cache's subscribe) and registers no query observer, so it does not fetch anything, never attaches an observer without a `queryFn` to the selector's query and re-renders only when that list changes. Until that list is cached, the cloud is unknown and nothing is gated.
* **Navigation.** `config.jsx` passes the menu through `withCloudSupport`, which adds `unsupportedClouds` to the pages the matrix lists. `filterMenuItems` hides a page when `unsupportedClouds` includes the `cloudEnvironment` option. You can also set `unsupportedClouds` on a nav item by hand. When the page's entry has a `navFallback`, the item stays and links there instead (JIT Admin opens its Requests tab for a government tenant).
* **Tabs.** `TabbedLayout` leaves out a tab whose page the matrix lists for the selected tenant's cloud (the JIT Admins tab); Commercial and AllTenants get the same tab list.
* **Direct URL.** `Layout` shows "Not available for GCC High tenants" with the matrix reason instead of rendering the page. The page's own API calls never run.
* **Actions.** `CippDataTable` and `HeaderedTabbedLayout` drop actions whose `url` is listed.
* **Standards and baselines pickers.** A listed standard keeps its place in the picker and shows a "Not supported in GCC High" chip with a tooltip: in the classic standards dialog, in both views of the baseline "Add Standards to Stage" catalog, and on a staged baseline standard's header (visible while collapsed). Templates apply to many tenants, so the standard is still applied to commercial tenants. The chip only appears when the tenant list contains a tenant in that cloud.
* **App registration permissions.** `CippAppRegistrationPermissions` resolves permission ids to names from service principals read through `ExecServicePrincipals`, which uses the partner tenant. 29 Graph permission ids differ in GCC High, so for an app in a government tenant the component passes `GovernmentTenantFilter` and `Invoke-ExecServicePrincipals` reads that tenant's service principals instead. A dedicated parameter, not `tenantFilter`: tenant-scoped callers such as the app approval template autocomplete send `tenantFilter`, and those requests must not cost a cloud lookup or change source. The backend honours `GovernmentTenantFilter` only for reads, only for a tenant whose cloud (`Get-CIPPTenantRequestCloud`) is not Commercial and only when the caller may access that tenant (`Test-CIPPAccess -TenantList`, then the scoped `Get-Tenants`); anything else is answered from the partner tenant as before. Without a government tenant the component sends the same requests and cache keys as before, and the other `ExecServicePrincipals` callers are unchanged. The risky-permission chips still match commercial ids only.

* **Portal links.** `portalHosts` in the matrix maps each commercial admin portal host to the government host Microsoft documents for USGovHigh and USGovDoD (sources in its `$comment`): Azure `portal.azure.us`, Entra `entra.microsoft.us`, Intune `intune.microsoft.us`, Defender `security.microsoft.us` / `security.apps.mil`, Power Platform `high.admin.powerplatform.microsoft.us` / `admin.appsplatform.us`, Purview `purview.microsoft.us` / `purview.apps.mil`. Portals with no documented government admin URL map to `null` and their links are not shown: the Microsoft 365 admin center partner links (`delegatedOrg`, `BeginClientSession`), the Exchange and Teams admin centers, the retired compliance portal and the Power BI admin portal. Only the host is replaced. `getCloudPortalUrl` (`src/utils/cloud-portal-links.js`) and the `useCloudPortalUrl` hook apply it in the tenant selector's portal shortcuts, the "View in Entra/Intune/Defender" buttons on detail pages, the Defender links in the quarantine and user-reported tables and the BEC report, and every row or header action `link` (through `filterCloudSupportedActions`). On the backend, `ConvertTo-CIPPCloudPortalUrl` applies the same map to the tenant list's `portal_*` columns and the Hudu and NinjaOne sync links. For Commercial, AllTenants and an unknown cloud every link is returned unchanged, and the backend's Commercial paths never read the map. Not covered: per-row links in an AllTenants table (the selected tenant's cloud is unknown), off-canvas action lists that do not go through `CippDataTable`'s action filter, and links about the partner tenant itself.

## Backend

`Test-CIPPCloudFeatureSupport -TenantFilter <t> -Type <section> -Name <key>` returns `$false` only for a government tenant and a listed feature. It reads the tenant's cloud with `Get-CIPPTenantRequestCloud`, the same rule the request helpers route by. It returns `$true` when the cloud cannot be resolved, so the job runs exactly as before. It never logs. If the backend copy of the matrix is missing or is not valid JSON, `Get-CIPPCloudFeatureSupport` logs one error per process and gates nothing, so jobs run as before and the #3 refusals still stop unsupported calls; it never throws, and it never reads the file for a Commercial tenant. Each caller first checks that the tenant's cloud is not Commercial, so Commercial tenants never reach the matrix.

| Job | Government tenant |
| --- | --- |
| Classic standards | Removed from the run in `Push-CIPPStandardsList`, which sets the compare field to "License Missing: Not supported for USGovHigh tenants." (with `LicenseAvailable` false) and writes one log line per tenant per run. The existing `License Missing:` marker means alignment scoring, drift and the applied-standards page treat the row exactly like a missing licence: left out of the alignment score and counted in License Missing, not graded Non-Compliant. `Push-CIPPStandard` also skips listed standards, without logging. |
| Baselines | The engine writes a `Skipped-Cloud` row with the reason before the licence check, and one log line per skipped standard per run, like a disabled standard. `Start-CIPPBaselineOrchestrator` is unchanged and does no cloud lookup. |
| Alerts | Recorded as `Skipped` in the alert run history, the task moves to its next slot, and one log line is written per run. |
| Tests | Removed from the suite, with one log line per tenant and suite run. |
| Cache collection | Removed from the collection, with one log line per tenant and collection run. |
| Audit log searches | Government tenants are left out of the 15-minute planner's fan-out, with one log line a day. |

### JIT Admin

JIT Admin stores its state in CIPP's `cippUser` schema extension. `Get-CIPPSchemaExtensions` reads and creates it in the partner tenant with CIPP-SAM, so it exists only in the partner's cloud; a government direct tenant of a commercial partner returns 500 "Resource 'ext..._cippUser' does not exist". `Get-CIPPJITAdminCloudError` returns the reason for such a tenant and nothing otherwise. Unlike `Test-CIPPCloudFeatureSupport` it refuses even when the matrix cannot be read (the matrix only supplies the text), and it does not refuse a government tenant in the partner's own cloud (`CIPP_PARTNER_CLOUD`). Every JIT path checks it before `Get-CIPPSchemaExtensions`:

| Path | Government tenant |
| --- | --- |
| `ListJITAdmin` | 400 with the reason |
| `ExecJITAdmin` | 400 with the reason, logged; nothing is scheduled and no approval request is stored |
| `Push-ExecJITAdminListAllTenants` (AllTenants list) | Tenant skipped, no cache row |
| `Set-CIPPUserJITAdmin` | Create and add actions throw the reason; removal, delete and disable still run |
| `Set-CIPPUserJITAdminProperties` | Writes nothing |
| `MFAAdmins` alert | Skips the "leave out JIT admins" filter (the tenant can have none) instead of failing the alert |

The JIT Admin templates, role templates and settings are stored in CIPP and are not tenant-bound, so they are not gated. `%cippuserschema%` replacements and custom data schema extensions are not JIT paths and were left as they are.

The UI matrix cannot tell the partner's cloud, so it hides the JIT Admins page for every government tenant, including on an instance whose partner is itself in that cloud.

## AllTenants

When gov and commercial tenants are mixed, a feature that fans out over tenants skips the government tenants and still runs for every commercial tenant. AllTenants standards, AllTenants alerts, the nightly cache and test runs, baselines and the audit log planner all work this way, because each of them checks the tenant it is running for.

In the UI, AllTenants has no single cloud, so nothing is hidden and no page is blocked. A government tenant's rows in an AllTenants report come back with the backend's refusal for that tenant, as they did before this change.

## Testing

* Pester: `Static/CloudFeatureSupportSync`, `GraphHelper/Test-CIPPCloudFeatureSupport`, `Private/JITAdmin.CloudSupport`, `Build/New-CippGovAppPermissions`, and the `*.CloudSupport` / `BaselineEngineCloudSupport` tests. Each one checks that a Commercial tenant takes the unchanged path and that a government tenant is skipped with one log line.
* Vitest: `tests/hooks/use-tenant-cloud.test.jsx`, `tests/utils/cloud-feature-support.test.js`, the `cloudEnvironment` cases in `tests/utils/filter-menu-items.test.js`, `tests/components/CippComponents/CippCloudSupportChip.test.jsx`, `tests/components/CippBaselines/CippBaselineCloudSupportChip.test.jsx`, `tests/utils/cloud-portal-links.test.js` and `tests/components/CippComponents/CippTenantSelector.cloudPortals.test.jsx`.
