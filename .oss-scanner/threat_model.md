# Threat model

## What CIPP is

CIPP is a multi-tenant Microsoft 365 management portal for managed service providers (MSPs). One CIPP instance belongs to one MSP. It holds an app registration (the SAM app) with GDAP delegated access to the customer tenants of one or more of the MSP's partner tenants, and acts on those tenants through Microsoft Graph, Exchange Online and other Microsoft APIs.

- `backend/` is PowerShell (Azure Functions programming model) running on the Craft runtime. A single HTTP trigger routes `/api/<Endpoint>` to `Invoke-<Endpoint>` in `backend/Modules/CIPPHTTP/Public/Entrypoints/`. Business logic is in `backend/Modules/CIPPCore`; the other `CIPP*` modules are standards, alerts, baselines, DB cache, extensions and tests.
- `frontend/` is a Next.js SPA (static export) that calls the backend only through `ApiGetCall`/`ApiPostCall` in `frontend/src/api/ApiCall.jsx`.
- `backend/Shared/CIPPSharp` is a C# helper library loaded by the backend.

Supported deployments run in Azure (CyberDrain-hosted or the MSP's own subscription). On-premises hosting is not supported; localhost and private-network URLs only appear in local development.

## Trust boundaries and where untrusted input enters

1. **Authenticated MSP staff (the main attack surface).** Sign-in is handled by Azure App Service Authentication (EasyAuth) in front of the app. It validates the Entra ID token and sets `x-ms-client-principal*` headers, which the backend trusts as identity. Requests then go through `Test-CIPPAccess`, which enforces:
   - a role per endpoint (readonly, editor, admin, superadmin, plus custom roles), and
   - a per-role allowed-tenant list, tenant groups and IP ranges.

   An editor scoped to tenants A and B must never read or change tenant C, CIPP's own settings or another user's role.
2. **API clients.** Entra app registrations calling the API with bearer tokens (`Get-CippApiClient`), with roles and IP ranges of their own. The MCP endpoint (`ExecMcp`) re-dispatches every tool call through the same router and `Test-CIPPAccess` checks.
3. **Unauthenticated endpoints.** `Invoke-Public*` (`PublicWebhooks`, `PublicPhishingCheck`, `PublicPing`, `PublicMcpRegister`) are reachable from the internet with no sign-in. Treat everything they receive as hostile.
4. **Data from customer tenants.** Any user in any managed tenant controls user names, group names, mail subjects, device names, audit-log fields and similar values. CIPP shows these to MSP staff and feeds them into PowerShell, OData filters, Exchange cmdlets, PSA/documentation integrations (Hudu, Halo, NinjaOne and others) and webhooks. This is the most important untrusted input, because a low-privileged user in one customer tenant should get no foothold in the MSP or in other customers' tenants.
5. **Integration responses.** PSA, RMM and documentation-tool APIs, and webhook destinations entered by staff (`Assert-CIPPWebhookDestination`).

## Components that matter most

- Authorisation: `backend/Modules/CIPPCore/Public/Authentication/` (`Test-CIPPAccess`, `Get-CIPPAccessRole`, `Resolve-CippImpersonation`, tenant-scope helpers) and the router `New-CippCoreRequest`.
- Tenant scoping: every endpoint that takes `tenantFilter`, a tenant list, a tenant group or "AllTenants", plus bulk/multi-tenant endpoints and scheduled tasks that run later on someone's behalf.
- Token and secret handling: SAM app credentials, refresh tokens, the token cache, certificates, Key Vault access, extension API keys and Password Pusher links.
- Anything that builds PowerShell, OData filters, KQL or Exchange cmdlet parameters from input. Existing guards include `ConvertTo-CIPPSafePwshArg`, `ConvertTo-CIPPODataFilterValue` and the scheduler function blocklist.
- Frontend rendering of tenant-controlled data (`getCippFormatting`, which sanitises with DOMPurify; drawers, dialogs and table cells).

## Out of scope

- Vendored third-party modules: `backend/Modules/AzBobbyTables`, `DNSHealth`, `HuduAPI`.
- The Craft runtime (separate repository) and EasyAuth, including how the `x-ms-client-principal*` headers reach the backend. Treat them as trusted identity.
- `build/`, `deployment/`, `docs/`, `user-documentation/`, `.github/` and test fixtures, except where they put a secret or a weakened setting into the shipped image.
- Missing Microsoft permissions or GDAP roles (a feature failing because a consent is missing is not a vulnerability).
- A superadmin or admin doing what their role allows, including reading secrets their role is meant to read.

## How to exercise it

- Backend: `pwsh backend/Tests/Invoke-CippTests.ps1 -NoExitCode` (Pester 5 is installed). Limit a run with `-Path backend/Tests/<folder>`. Tests dot-source the function under test and stub its dependencies (Graph, Table Storage), so no Azure resources are needed. `backend/Tests/Private` (the `Test-CIPPAccess` role matrix), `Security`, `Endpoint` and `Static` hold the closest examples of access-control tests.
- Frontend: `cd frontend && yarn test:unit` (vitest).
- No live Microsoft 365 tenant or Azure storage is available offline. Show a backend issue with a Pester test that stubs `New-GraphGetRequest`/`New-GraphPOSTRequest`/`New-ExoRequest`/`Get-CIPPAzDataTableEntity` and calls the entrypoint with a crafted `$Request`.

## How we rate severity

- **Critical:**
  - authentication bypass, or any unauthenticated action on a tenant or on CIPP settings;
  - reading or changing a tenant that the caller's role does not allow (cross-tenant access);
  - disclosure of SAM credentials, refresh tokens, certificates or Key Vault secrets to a non-superadmin;
  - remote code execution in the backend;
  - customer-tenant data that reaches code execution or Graph actions with the MSP's privileges.
- **High:**
  - privilege escalation between CIPP roles (readonly to editor, editor to admin, a custom role exceeding its permissions);
  - stored XSS where the payload comes from customer-tenant data or an unauthenticated endpoint;
  - SSRF that reaches the instance's managed identity or metadata endpoint;
  - an IP-range restriction that can be bypassed.
- **Medium:**
  - stored XSS that needs an authenticated CIPP user to plant it;
  - injection into an OData filter or Exchange cmdlet that stays within the caller's own allowed tenants and role;
  - information disclosure of non-secret data across CIPP users;
  - CSRF on a state-changing endpoint.
- **Low:**
  - denial of service, which needs an authenticated user or only affects the caller;
  - issues only reachable by a superadmin.
- **Informational:**
  - missing hardening with no demonstrated impact;
  - verbose errors.

A post-auth finding is rated by the lowest role that can trigger it. Treat an editor-reachable cross-tenant bug as critical, not high.

We re-assess every finding's severity on triage, and remediation timeframes follow that assessment.

## Anything to leave alone

- PowerShell style (`+=`, aliases, missing `[CmdletBinding()]`) is not a security issue.
