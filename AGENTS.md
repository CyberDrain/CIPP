# CIPP — agent and contributor guide

CIPP (CyberDrain Improved Partner Portal) is a multi-tenant Microsoft 365 management portal for MSPs.
Monorepo: **Next.js frontend + PowerShell backend**, shipped as one container.

This is the single source of guidance for contributors and AI coding agents (Claude, Codex/ChatGPT, Copilot).
`CLAUDE.md` and `.github/copilot-instructions.md` point here. Task-specific guides live in `.github/agents/`:

| Task | Guide |
| --- | --- |
| HTTP endpoints (`Invoke-List/Add/Edit/Remove/Exec*`), status codes, cached list reads, tenant groups | `.github/agents/CIPP-Endpoint-Agent.md` |
| New standards (Baselines) | `.github/agents/CIPP-Standard-Agent.md` |
| Scripted alerts (`Get-CIPPAlert*`) and their `alerts.json` entry | `.github/agents/CIPP-Alert-Agent.md` |
| In-app compliance tests (`Invoke-CippTest*`) and the custom-test sandbox | `.github/agents/CIPP-Test-Agent.md` |

---

## 1. The runtime model (read this first)

There is **no Node API server and no Azure Functions host**. The backend is PowerShell modules
executed by **[Craft](https://github.com/CyberDrain/Craft)**, a .NET runtime that hosts a pool of
PowerShell workers, serves the static Next.js export, and handles auth, scheduling and orchestration.

```
browser ──▶ Craft (ASP.NET, port 8080 → host 5196)
              ├── serves frontend/out (static export)   [prod]
              ├── proxies non-/api routes to Next dev   [dev, CRAFT_DEV_FRONTEND_URL]
              └── /api/<Endpoint>
                    └── New-CippCoreRequest  (the single HTTP dispatcher)
                          └── Invoke-<Endpoint>  in module CIPPHTTP
                                 └── CIPPCore helpers → Graph / Exchange / Azure Table
```

Storage is **Azure Table/Blob/Queue** (Azurite locally). There is no SQL database.
`$env:AzureWebJobsStorage` is the connection string; `Get-CIPPTable -TableName X` is the accessor.

Craft's behaviour is configured in `build/config/appsettings.*.json`: which modules load, which function is the HTTP
handler, where timers come from. When something behaves oddly at the runtime level, look there before reading
PowerShell.

---

## 2. Repo layout

| Path | What it is |
| --- | --- |
| `frontend/` | Next.js 16 / React 19 / MUI 7 app. `output: 'export'` → static, builds to `frontend/out`. Pages Router (`src/pages`), **not** App Router. |
| `backend/Modules/CIPPHTTP/` | **Every HTTP endpoint.** One `Invoke-*.ps1` per endpoint under `Public/Entrypoints/HTTP Functions/<Area>/`. |
| `backend/Modules/CIPPCore/` | Shared logic + helpers (Graph, Exchange, tables, auth, tenants) and timer/orchestrator entrypoints. |
| `backend/Modules/CIPPStandards/` | The ~210 classic tenant "standards". **Bugfixes only**: new tenant configuration work goes in Baselines. |
| `backend/Config/BaselineStandards/` + `CIPPBaselines/` (engine, hooks, executors) + `CIPPCore/Public/Baselines/` (HTTP-facing) | **Baselines**: drift-first declarative standards (definition JSON + optional prepare hook / executor). All new standard work lands here. |
| `backend/Modules/CIPPAlerts/` | `Get-CIPPAlert*.ps1` scheduled alert checks. |
| `backend/Modules/CIPPTests/` | In-app compliance tests (CIS / CISA / E8 / EIDSCA / ORCA). Not unit tests. |
| `backend/Modules/CIPPDB/` | `Set-CIPPDBCache*`: populates the report cache tables that "UseReportDB" list endpoints read. |
| `backend/Shared/CIPPSharp/` | C# helpers loaded into every worker (`[CIPP.CippJson]`, `[CIPP.CippIndex]`, `[CIPP.TestDataCache]`, ...). |
| `backend/Config/` | JSON config + built-in templates shipped with the app. |
| `backend/Tests/` | **Pester** unit tests. Runner: `backend/Tests/Invoke-CippTests.ps1`. |
| `build/` | Dockerfiles, compose files, `tools/` dev scripts, `config/appsettings.*.json`. |
| `deployment/` | Bicep/ARM templates for Azure deploys. |
| `docs/` | GitBook source for docs.cipp.app. |

---

## 3. Backend: adding or changing an endpoint

### Routing is pure convention
`GET /api/ListGroups` → `Invoke-ListGroups`. The dispatcher builds the name as
`'Invoke-{0}' -f $Request.Params.CIPPEndpoint`. **There is no route table to register in.**
Drop the file anywhere under `CIPPHTTP/Public/Entrypoints/HTTP Functions/`; folders are for humans.

Verb prefixes in use: `List` (read), `Add`, `Edit`, `Remove`, `Exec` (everything else / actions).

### Anatomy

```powershell
function Invoke-ExecThing {
    <#
    .FUNCTIONALITY
        Entrypoint            # required. add ",AnyTenant" if it must run without a tenant
    .ROLE
        Identity.User.ReadWrite   # required. gates access
    .DESCRIPTION
        Shown in generated API docs.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter   # POST; use $Request.Query.tenantFilter for GET

    if (-not $Request.Body.UserId) {             # validate BEFORE the try; also marks the field required in OpenAPI
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'UserId is required' } })
    }

    try {
        $Result = Do-Work -TenantFilter $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_   # 400/404 from typed helper throws, else 500
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ 'Results' = $Result }
    })
}
```

**Response shape matters; the frontend depends on it:**
- **Action endpoints** (`Add`/`Edit`/`Remove`/`Exec`): `Body = @{ Results = ... }`.
  `CippApiResults` renders `Results`/`Result` (string, or array of `{resultText, state}`).
- **List endpoints**: return the array directly: `Body = @($Data)`. Tables consume it as rows.

Always pass `-tenantid` to `New-GraphGetRequest`, `New-GraphPOSTRequest`, `New-GraphBulkRequest` and `New-ExoRequest`.
Omitting it hits the partner tenant instead of the customer.

### Status codes (full guide: `.github/agents/CIPP-Endpoint-Agent.md`)
The status code must say what happened. Craft caches 2xx GETs (600 s), MCP treats `>= 400` as an error, and the
frontend's retry and render logic keys off the status. A failure returned as 200 is cached and shown as data.

| Situation | Status |
| --- | --- |
| success (202 if queued) | 200 |
| invalid input / refused by business rules | 400 |
| a named resource is missing | 404 |
| CIPP's own access check (role, allowed tenants, `Test-CIPPAccess`), **never** "Graph said no" | 403 |
| Graph / EXO / SPO / Azure / table failure, or anything unexpected | 500 |
| multi-item: all ok / some failed / all failed | `Get-CippBulkStatusCode -Total -Failed` → 200 / 207 / 500 |

- A `catch` never returns `OK`. `Tests/Static/CatchBlockStatusCode.Tests.ps1` enforces this, with an allow-list for
  deliberate fallbacks (polled status endpoints, JSON-RPC, empty-is-valid lookups).
- Helpers throw `[System.ArgumentException]` for input/refusal and `[System.Management.Automation.ItemNotFoundException]`
  for not-found; upstream errors throw untyped. `Get-CippErrorStatusCode` follows `InnerException`, because a
  `.Invoke()`d script block wraps the error two levels deep. Never rethrow a typed error as a string.
- Multi-item helpers return `@{ resultText; state }` per item instead of swallowing failures into strings. Check
  every caller first: background callers (user tasks, offboarding, BEC containment, extension syncs) must keep collecting.
- Frontend: no retry on 4xx except 408/429. Multi-row actions report a failed row (`onResult(row, { failed: true })`)
  and keep going. 207 is a success to axios, and each item's `state` decides how it renders.

### Permissions
`.ROLE` is extracted **at runtime by Craft** into `backend/Config/function-permissions.json`
(gitignored, regenerated on container start; never hand-edit it). Role→permission mapping for the
four built-in roles lives in `backend/Config/cipp-roles.json`. Permission strings are
`Area.Object.Read` / `.ReadWrite`, with `CIPP.SuperAdmin.*` reserved.

### The OpenAPI spec is generated from your entrypoint
`backend/Config/openapi.json` is built by `build/tools/build-openapi.ps1`, which parses every
entrypoint with the **PowerShell AST** and derives the request schema from what the code reads.
It is committed, and it is **not documentation-only**: `Get-CippMcpSpec` loads it at runtime and
`Get-CippMcpToolCatalog` projects every `.Read` operation in it into an MCP tool. A stale spec ships a
stale tool contract. CI (`.github/workflows/openapi_spec.yml`) fails the PR if it drifts.

`tools/list` does not return all ~260 of them. `Get-CippMcpToolList` advertises a fixed five-tool gateway
(`ListTenants`, `ListGraphRequest`, `SearchTools`, `GetToolInfo`, `ExecTool`) and the model reaches the rest by
searching, fetching a schema with `GetToolInfo`, and running it via `ExecTool`. Every `.Read` operation is still a
tool, so your endpoint's summary/description is what makes it **findable**.

Two rules the projection enforces:

- **A parameter name must survive MCP's `^[a-zA-Z0-9_.-]{1,64}$`.** Reading an OData option straight
  off the request (`$Request.Query.'$filter'`) puts a `$` in the schema. `Get-CippMcpSafePropertyName` renames it
  (`$filter` → `odata_filter`) and `Invoke-CippMcpApiRequest` reverses it on dispatch.
- **A `$ref` that resolves to nothing must not throw**, or one bad parameter takes down the entire catalog.

When writing an endpoint:

- **Nested reads are documented as nested.** `$Request.Body.user.value` emits a `LabelValue` object, not a string.
- **Types come from usage**: `[bool]$Request.Body.x`, `-as [int]`, `switch` (becomes an `enum`), `foreach` (becomes
  an array). Nothing to annotate; just write normal PowerShell.
- **Comments above a request read become the field description.** This is the only field-level documentation there is.
- **A guard that rejects a missing field marks it `required`**: `if (-not $Request.Body.X) { throw }`.
- `.SYNOPSIS` / `.DESCRIPTION` become the operation summary/description, and `Entrypoint,AnyTenant`
  makes `tenantFilter` optional.
- Reading `$Request.Body` and forwarding it whole flags the schema `x-cipp-passthrough` with an open
  schema. Read the fields you use if you want them documented.

The spec needs regenerating after an endpoint's request contract changes, but **ask the maintainer before running
the generator.** It rewrites the whole of `openapi.json`, so it sweeps up unrelated in-flight changes and makes the
diff unreviewable. The dev module watcher regenerates it automatically, and CI reports drift. When asked:
```bash
pwsh build/tools/build-openapi.ps1
```
For the few endpoints whose contract can't be read statically, add a deep-merged override in
`backend/Config/openapi-overrides/` (see the README there). Prefer teaching the generator a pattern over an override.

### Helper vocabulary (don't reinvent these)
`backend/Modules/CIPPCore/Public/GraphHelper/`:

| Need | Use |
| --- | --- |
| Graph GET (auto-paginates) | `New-GraphGetRequest -uri ... -tenantid $Tenant` (`-AsApp $true`, `-ComplexFilter`, `-Stream` for big sets) |
| Graph write | `New-GraphPOSTRequest` |
| Many Graph calls at once | `New-GraphBulkRequest` + `Get-GraphBulkResultByID` |
| Copilot usage report | `Get-CIPPCopilotReport -UriTemplate "...(period='{0}')" -TenantFilter $T` (D28, retries D30 on Graph's period error) |
| Exchange Online cmdlet | `New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox'` (`New-ExoBulkRequest` for batches) |
| Azure Table | `$Table = Get-CIPPTable -TableName 'X'` then `Get-CIPPAzDataTableEntity @Table -Filter "..."` / `Add-CIPPAzDataTableEntity` |
| Tenant list | `Get-Tenants` |
| Persisted tenant reference | store `customerId`, never the domain; resolve stored values with `Get-CIPPTenantLookup` (see §6) |
| Audit log / user-visible log | `Write-LogMessage -API 'Standards' -tenant $Tenant -message '...' -sev Info\|Warn\|Error -headers $Headers` |
| Friendly Graph error | `Get-NormalizedError -Message $_.Exception.Message` |
| Status for a caught error | `Get-CippErrorStatusCode -ErrorRecord $_` (ArgumentException 400, ItemNotFoundException 404, else 500) |
| Status for a multi-item request | `Get-CippBulkStatusCode -Total $n -Failed $m` (200 / 207 / 500) |
| AllTenants list read | `Get-CIPP<X>Report` (paged via `Get-CIPPReportPage` only when `manualPagination` is set) or `Get-GraphRequestList -TenantFilter 'AllTenants'` (see §6) |
| Lookup over rows | a hashtable, or `[CIPP.CippIndex]` (`.First($Key)` / `.Find($Key)`) for many rows per key |
| JSON | `[CIPP.CippJson]::ToJson($X, $Depth)` / `[CIPP.CippJson]::ConvertFromJson($Json)` (see §6) |

### Subsystems and how to register in each

**Baselines** (`backend/Config/BaselineStandards/<Category>/<Name>.json`, plus
`CIPPBaselines/Public/PrepareHooks/Get-CIPPBaseline<Name>State.ps1` / `Executors/Invoke-CIPPBaseline<Name>.ps1`
only when needed). CIPPBaselines is background-only: preloaded into background workers via `BgModules` (with CIPPDB,
CIPPTests, CIPPAlerts), never loaded by HTTP workers. Anything an HTTP endpoint calls stays in
`CIPPCore/Public/Baselines/`; `Tests/Static/BaselinesModuleBoundary.Tests.ps1` enforces it. **Every new standard is a
baseline**: follow `.github/agents/CIPP-Standard-Agent.md`. Tests go in `backend/Tests/Baselines/`;
`BaselineDefinitions.Catalog.Tests.ps1` checks every definition resolves. No frontend registration: the catalog is
read from the JSON folder at runtime.

**Classic standards: bugfixes only, no new standards or features**
(`CIPPStandards/Public/Standards/Invoke-CIPPStandard<Name>.ps1`)
`param($Tenant, $Settings)`. The comment block is the schema: `CAT`, `TAG`, `ADDEDCOMPONENT` (JSON form fields),
`IMPACT`, `POWERSHELLEQUIVALENT`, `RECOMMENDEDBY`, `REQUIREDCAPABILITIES`. It drives `frontend/src/data/standards.json`,
the generated file the UI renders. The body handles three modes off `$Settings`: report, alert, remediate.

**Alerts** (`CIPPAlerts/Public/Alerts/Get-CIPPAlert<Name>.ps1`)
Also needs a matching entry in `frontend/src/data/alerts.json` to be selectable in the UI. Both halves:
`.github/agents/CIPP-Alert-Agent.md`.

**In-app tests** (`CIPPTests/Public/Tests/<Framework>/<Area>/Invoke-CippTest<Id>.ps1`)
`param($Tenant)`. Read cached data via `Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'`, report via
`Add-CippTestResult`. Fields a test reads must be in `Get-CippTestDataFieldManifest` (unlisted fields read as `$null`,
silently). Full guide: `.github/agents/CIPP-Test-Agent.md`.

**Scheduled work**: `backend/Config/CIPPTimers.json` (cron + command). Commands live in
`CIPPCore/Public/Entrypoints/Timer Functions` and `Orchestrator Functions`.

---

## 4. Frontend: page patterns

Every page is `src/pages/<area>/<...>/index.jsx` and **must** end with:

```jsx
Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>
export default Page
```

Add `allTenantsSupport={true}` when the page works with the "AllTenants" selection, and `usesTenant={false}` when
it never uses the selected tenant (settings, templates), so a tenant group selection doesn't block it.

### List page → `CippTablePage`
```jsx
<CippTablePage
  title="Users"
  apiUrl="/api/ListUsers"          // tenantFilter is injected automatically
  queryKey="ListUsers"             // react-query cache key; also the invalidation target
  actions={useCippUserActions()}
  simpleColumns={['displayName', 'userPrincipalName']}  // whitelist; otherwise columns are inferred
  offCanvas={{ extendedInfoFields: [...], actions: [...] }}
  filters={[{ filterName: 'Enabled', value: [{ id: 'accountEnabled', value: 'Yes' }], type: 'column' }]}
  cardButton={<CippAddUserDrawer />}
/>
```

### Form page → `CippFormPage`
Wraps `react-hook-form` (`formControl` prop) + a POST pipeline (`postUrl`, `queryKey`).
Fields go through `<CippFormComponent type="..." name="..." formControl={formControl} />`.
Available `type` values: `textField`, `textFieldWithVariables`, `number`, `password`, `switch`,
`checkbox`, `radio`, `select`, `autoComplete`, `datePicker`, `richText`, `colorPicker`, `file`,
`CSVReader`, `cippDataTable`, `hidden`, `heading`, `alert`, `CountryCodeMultiSelect`,
`LanguageCodeMultiSelect`. Conditional fields: wrap in `<CippFormCondition>`.

### Row actions
An action is an object in the `actions` array, either a link or an API call:
```jsx
{ label: 'View User', link: '/identity/administration/users/user?userId=[id]', icon: <EyeIcon /> }
{ label: 'Disable', type: 'POST', url: '/api/ExecDisableUser',
  data: { ID: 'id', Enable: '!true' },   // see mapping rules below
  fields: [ /* CippFormComponent specs, rendered in a dialog */ ],
  customDataformatter: (row, action, formData) => ({ ... }),
  confirmText: 'Disable [userPrincipalName]?',
  condition: (row) => canWriteUser }
```
`CippApiDialog` renders it; `CippApiResults` renders the response.

**`data` mapping rules** (`processActionData` in `CippApiDialog.jsx`):
a string value is treated as a **row property name** (`ID: 'id'` sends `row.id`), falling back to the
literal if the row has no such key. Prefix with `!` to force a literal (`Enable: '!true'` sends the
string `"true"`). Objects recurse. `postEntireRow: true` on `api` sends the whole row.
`replacementBehaviour: 'removeNulls'` drops empty values. In `confirmText`/`link`, `[field]` is
interpolated from the row instead.

### Data fetching
Always via `src/api/ApiCall.jsx`, never raw `axios`/`fetch`:
- `ApiGetCall({ url, queryKey, data, waiting, relatedQueryKeys })`
- `ApiPostCall({ relatedQueryKeys, onResult })` → `.mutate({ url, data, bulkRequest })`
- `ApiGetCallWithPagination(...)` for `Metadata.nextLink` paging

`relatedQueryKeys` invalidates other caches after a write and supports `'ListUsers*'` wildcards and
`'*'` (everything). There is no axios `baseURL`: the API is same-origin, hence dev on **:5196**.

### Cross-cutting hooks
`useSettings().currentTenant`: the selected tenant (persisted Redux, `SettingsContext`). A tenant group selection is
`'group:<id>'`: build request params from it with `tenantScope(...)` (`utils/tenant-selection`), never send it as
`tenantFilter`. Opt-in rules for pages and endpoints: "Tenant groups" in `.github/agents/CIPP-Endpoint-Agent.md`.
`usePermissions().checkPermissions(['Identity.User.ReadWrite'])` reads `/api/me`.
`PermissionButton` from `utils/permissions` for permission-gated buttons.

### Navigation
New pages **must** be added to `src/layouts/config.js` (`nativeMenuItems`) to appear in the sidebar.
Each entry carries a `permissions: ['Identity.User.*']` array that hides it from unauthorized users.

---

## 5. Development

Local dev is Docker-based; everything is served same-origin on **http://localhost:5196**.
`:3000` is the raw Next dev server (don't use it directly: API calls will 404). Setup:
`docs/dev-documentation/cipp-dev-guide/setting-up-for-local-development.md`.

**Windows** (one command, opens three Windows Terminal tabs: API+Azurite, module watcher, frontend):
```bash
pwsh ./build/tools/Start-Cipp-Dev-Windows-docker.ps1
```

**Linux** (frontend also containerized):
```bash
cd build && docker compose -f docker-compose-all.yml up --pull always --watch
```

- Backend modules are ModuleBuilder-compiled. Edits under `backend/Modules|Shared|Config` restart the API container
  automatically; on Windows the module watcher recompiles first.
- All dev data lives in the `cipp-ng_azurite-data` volume. Delete it for a factory reset.
- Frontend-only work: `cd frontend && yarn dev`, but browse via :5196 so `/api` resolves.

**Calling the dev API from a script: use `127.0.0.1`, never `localhost`.** `localhost` resolves to IPv6 `::1` first,
and PowerShell's web cmdlets stall ~21 s per request before falling back (35 ms on `127.0.0.1`). For a loop of more
than a handful of requests, reuse one client instead of spawning `curl.exe` per call:

```powershell
$Handler = [System.Net.Http.HttpClientHandler]::new()
$Handler.UseProxy = $false
$Client = [System.Net.Http.HttpClient]::new($Handler)
$Client.GetStringAsync('http://127.0.0.1:5196/api/ListTenants').GetAwaiter().GetResult()
```

**Never run a production build** (`yarn build`, `next build`, or the Docker image build) to verify a change. It is
slow, and `yarn build` ends with `rm -rf package.json yarn.lock`. Use the checks below; if something genuinely can't
be verified without a build, say so.

**Checks before you call something done:**
```bash
cd frontend && npx eslint . && npx prettier --check '**/*.{js,jsx,json}'
```
```bash
pwsh -c "Invoke-ScriptAnalyzer -Path ./backend -Recurse -Severity Error,Warning -ExcludeRule PSAvoidUsingWriteHost"
```
```bash
pwsh ./backend/Tests/Invoke-CippTests.ps1                                # all Pester tests
pwsh ./backend/Tests/Invoke-CippTests.ps1 -Path backend/Tests/Standards  # one area
```
CI runs PSScriptAnalyzer (errors block merge), JSON validation, CodeQL, and conventional-commit checks.
A Pester file whose code under test uses a `[CIPP.*]` type must `Add-Type` `Shared/CIPPSharp/bin/CIPPSharp.dll` in
`BeforeAll` (`New-CippTest.ps1` adds it): helpers such as `Add-CIPPDbItem` fall back silently without it and the test
passes on the wrong path. Changes that write table rows (cache helpers, CippJson, `Add-CIPPDbItem`) also need one real
run through Craft: in-process harnesses never write, so a row that cannot be read back only shows up there.

**Frontend vitest**: the full unit project takes minutes, so while iterating run one file by path:
```bash
cd frontend && npx vitest run --project unit tests/components/<Area>/<Name>.test.jsx
```
`--changed` is not a shortcut (it still walks the whole import graph). A single 15 s timeout in a full run is usually
load: re-run that file alone before calling it a regression. Conventions:
`docs/dev-documentation/cipp-dev-guide/frontend-testing.md`.

---

## 6. Conventions

### Pull requests
All PRs target **`dev`**; `main` is release-only. Keep PRs focused (a fix and a feature are separate PRs). When a
change alters what a user sees or can do, update the matching page under `docs/` in the same PR
(`docs/dev-documentation/contributing-to-the-documentation.md`).

### Commit messages
**Conventional Commits**, enforced by CI: `<type>(<optional scope>): <description>`.

- Type: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Scope: optional short lowercase area name (`feat(identity):`).
- Description: imperative ("add", not "added"), lowercase, no trailing period, ideally ≤ 72 characters.
- Keep it simple: a subject line, plus a few short bullets only if needed. No measurements, investigation narrative
  or per-change rationale.
- Breaking changes: `!` before the colon and/or a `BREAKING CHANGE:` footer.
- Work for a GitHub issue ends the message with a `Fixes #<n>` line (one per issue).

```
feat(identity): add bulk user offboarding endpoint
fix(graph): handle expired token on retry
refactor(standards)!: rename remediation parameter
```

### Style
- **Comments**: default to none on new code. Use at most one short line where the why is genuinely not obvious.
  Much of the backend is heavily commented; don't copy that density.
- **Frontend style**: Prettier: `singleQuote: true`, `semi: false`, `tabWidth: 2`, `trailingComma: es5`.
  Much of the tree predates this config and still uses double quotes + semicolons. Match the **file you are
  editing**; don't reformat unrelated files.
- **JS**: `.js` and `.jsx` are both used and mean nothing in particular. No TypeScript (the `typescript`
  devDependency is only there for Next's tooling).
- **PowerShell style**: PascalCase locals (`$TenantFilter`), single quotes for plain strings, `try/catch` around every
  external call, `Write-LogMessage` for anything the user should see.
- **Dependencies**: use native APIs over PowerShell modules. Every module slows every worker; the backend loads only
  `Az.Keyvault` and `Az.Accounts`.

### Helper functions
Every function is one more place a contributor has to look, so a new one has to earn its place.

- Write logic that has one caller inline where it is used. Add a function only when it has two or more real callers,
  or it is a generic building block like the helpers in §3.
- Don't wrap a single call to an existing function: call the existing function directly.
- Don't declare functions inside functions. Put the branch inline, or compute the input first and classify it once.
- Search for an existing helper before writing one, and extend it rather than adding a near-copy.

### Storing tenant references
A tenant's default domain can change (`contoso.onmicrosoft.com` becomes `contoso.com`); its `customerId` cannot.
Anything that persists a tenant (table keys and columns, saved settings, JSON stored for later) stores the
`customerId`. Anything keyed by an old domain silently becomes a second tenant.

- Resolve stored values through `Get-CIPPTenantLookup`, built once per call. It maps `customerId`, default domain and
  initial domain to the tenant, so values saved as a domain before this rule still resolve. Use the tenant's current
  `defaultDomainName` for Graph calls, logs and display.
- Match stored values on the tenant, never on the raw string: existing rows may still hold a domain.
- Don't call `Get-Tenants -TenantFilter` once per stored value. An unknown value sends it down its refresh path.
- Results rebuilt on every run (report caches, baseline alignment rows) can stay keyed by the current default domain.

### Cached list reads
AllTenants List reads come from the reporting database (`Get-CIPP<X>Report`, paged through `Get-CIPPReportPage`) or
the graph request cache (`Get-GraphRequestList -TenantFilter 'AllTenants'`). Full guide: "Cached list reads" in
`.github/agents/CIPP-Endpoint-Agent.md`.

- Paging is opt-in with `manualPagination`; without it a report-backed endpoint returns the whole report as an array.
- Never add a cache table that writes new random RowKeys on each refresh and is read whole, then filtered by
  `Timestamp` in PowerShell. It grows without bound.
- Frontend pages use `useCippReportDB({ serverPagination: true })` and pass its `resolvedApiData` and `apiDataKey`.

---

## 7. Performance: PowerShell hot paths

Code that runs per row or per batch (cache collectors, `Push-*` activities, post-execution, report folds, alerts,
in-app tests, baseline hooks) runs for every tenant, and tenants with 50k users or 20k mailboxes are normal. Moving
to pwsh 7.6 / .NET 10 changed allocation by about 1%; the patterns below cut the same mailbox-permissions path by 24%.
**If it is not fast, it is not good.**

**Loops and lookups**
- Filter with `foreach` + `if` or `.Where({ })`, never `| Where-Object`. Per 100k rows: `foreach` 51 ms / 2.6 MB,
  `.Where()` 201 ms / 101 MB, `Where-Object` 1,024 ms / 401 MB. The pipeline is the cost, whatever the row type.
- Build a lookup once (hashtable, `HashSet`, `[CIPP.CippIndex]`, whose `.First($Key)` replaces
  `.Find($Key) | Select-Object -First 1`) instead of scanning inside a loop. A `Where-Object` scan of 50k rows costs
  ~350 ms, so a scan per user is minutes.
- `.Where()` returns a collection even for zero or one match. `.github/agents/CIPP-Test-Agent.md` lists the cases where
  that differs from the pipeline result.
- No `| Select-Object -First` on a hot path: it throws to stop the pipeline. Use `$X.Where({ P }, 'First')[0]` or
  `@($X)[0]`; indexing an empty collection also throws internally, so where it is usually empty use
  `foreach ($Item in $X) { $First = $Item; break }`.
- Clamp range slices: `$X[$i..([Math]::Min($i + 19, $X.Count - 1))]`. Each index past the end throws and is caught
  internally, so `$X[$i..($i + 19)]` over 3 items costs 17 exceptions.
- Never invoke a script block per row or per field (`& $Helper $Value`, ~60 µs / 9 KB each): each call builds a
  command processor and binds parameters. Inline the loop, or move the logic into CIPPSharp when it is per field.
  A PowerShell function call costs ~20 µs too, so keep per-record work out of helpers that wrap one .NET call.
- `foreach ($X in @(Big-Call))` keeps the whole result alive until the function returns. Fine for small sets; pipe
  large ones (mailboxes, sign-ins, audit records) instead.

**Collections**
- Never `+=`, to grow an array or anywhere else (`$Hash['k'] = $Hash['k'] + $Item` counts). Build in one `@(...)`
  subexpression (emit the items, including a conditional `if ($Cond) { $X }`), assign a `foreach` to a variable, or
  use `[System.Collections.Generic.List[object]]` + `.Add()`.
- Never `Select-Object` / `Sort-Object` / `Group-Object` over hashtables or `-AsHashtable` output: 20–80 s per 100k
  rows against 1–2 s for objects. `[ordered]` dictionaries silently break them: the keys are not treated as properties.
- On a dictionary whose keys come from data, use `$Dict.PSBase.Count` / `$Dict.PSBase.Keys`: member access prefers
  keys, so a field named `count` or `keys` silently replaces `.Count` / `.Keys`.

**Objects**
- `[PSCustomObject]@{}` costs ~4 KB per 6-field row to build. Build it once per output row, never as an intermediate.
- Don't `PSObject.Copy()` unless you then mutate an object someone else still reads.
- Don't `Add-Member -NotePropertyName` per row (it throws internally while binding):
  `$Row.PSObject.Properties.Add([psnoteproperty]::new('Name', $Value))`. `Add-Member -Force` is `$P.Remove('Name')`
  followed by that `Add` (the property moves to the end, as with `-Force`). For several members on one record, one
  `Add-Member -NotePropertyMembers` call. Test for a property with `$null -ne $Row.PSObject.Properties['Name']`, not
  `$Row.PSObject.Properties.Name -contains 'Name'` (a full walk).
- Don't enumerate `.PSObject.Properties` / `.PSObject.Members` per row to read fields: it builds member sets and leaves
  them attached to every row. In CIPPSharp C#, read a row's fields with `PSMembers.InstanceProperties` (it skips hidden
  members; once anything has enumerated `Properties`, the reserved `pstypenames` sits among the instance members).

**JSON and strings**
- Serialise with `[CIPP.CippJson]::ToJson($X, $Depth)` and fall back to `ConvertTo-Json` when it returns `$null`
  (4× faster on PSCustomObject rows). Parse with `[CIPP.CippJson]::ConvertFromJson($Json)`, passing a field list when
  only some fields are read. Parse a `CIPPRestClient` result with `[CIPP.CippJson]::ConvertFromResponse($Result)`: it
  reads the UTF-8 body bytes without building `$Result.Content`. Test for a body with `$Result.HasContent`.
- No `ConvertTo-Json` inside log, `Write-Information` or markdown strings that are built whether or not they are read.
- Give string transforms an early exit: `Get-CIPPTextReplacement` used to do table reads and ~10 regex passes on
  every body, although almost none held a `%` token.

**Per-call helpers** (every request, standard or test hits them: tenant lookups, capabilities, tokens)
- Count table queries per call, not just PowerShell cost. Defer reads to the branch that uses them and filter
  server-side.
- Don't re-read a table and re-parse JSON on each call: keep a short-lived per-tenant result
  (see `Get-CIPPTenantCapabilities`).
- Read an environment variable that may be unset with `[System.Environment]::GetEnvironmentVariable('Name')`: `$env:Name`
  throws and catches an exception internally every time the variable is missing.

**Proving a change**
- Measure real shapes (a 50k-user tenant, not 10 rows), time **and** allocation, before and after.
- Measure in the Linux containers (`mcr.microsoft.com/dotnet/sdk` images), not Windows pwsh: Windows adds ~10–20 µs
  and ~1 KB of AMSI logging to every .NET method call, which hides or invents wins.
- PowerShell hashtable key order differs per process: canonicalise JSON (sorted keys) before diffing two runs.

---

## 8. Gotchas that cost time

- **Don't grep for route definitions.** Endpoint routing is name-based (`/api/X` → `Invoke-X`).
  To find the handler for an API call, search for the function name, not the URL.
- **`backend/Config/function-permissions.json` is generated at runtime** and gitignored. Changing
  `.ROLE` in the source is the only correct way to change permissions.
- **`frontend/src/data/standards.json` is generated** from the classic standards' comment blocks. Edit the
  PowerShell comment block, not the JSON.
- **`backend/Config/openapi.json` is generated** from the entrypoint AST and committed. Never hand-edit it; change
  the entrypoint (or add an override). Ask before regenerating it (§3).
- **`frontend/src/data/M365Licenses.json` is ~2 MB.** Never read it whole; grep for the SKU.
- **`out/` and `node_modules/` exist in-tree**: exclude them from searches.
- **Next.js is a static export.** No API routes, no SSR, no server components, no middleware.
  Anything server-side belongs in the PowerShell backend.
- **List endpoints frequently have a cached path** (`UseReportDB=true` / `tenantFilter=AllTenants`)
  that returns data from `CIPPDB` cache tables instead of live Graph. If a list looks stale or has
  different columns than expected, check for the `Get-CIPP*Report` branch.
- **`retry`/toast behaviour is centralized** in `ApiCall.jsx`; a 302 to `/.auth/login/aad` means the
  session expired and triggers re-auth, it is not a routing bug.
