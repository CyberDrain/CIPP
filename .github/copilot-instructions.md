## Commit messages

Generate all commit messages in **Conventional Commits** format:

```
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

**Rules:**

- **Type** is required and must be one of:
  - `feat` — a new feature
  - `fix` — a bug fix
  - `docs` — documentation only
  - `style` — formatting, whitespace, no code-behavior change
  - `refactor` — code change that neither fixes a bug nor adds a feature
  - `perf` — a performance improvement
  - `test` — adding or correcting tests
  - `build` — build system or dependency changes
  - `ci` — CI/CD configuration changes
  - `chore` — routine maintenance, no production code change
  - `revert` — reverts a previous commit
- **Scope** is optional and given in parentheses after the type (e.g. `feat(identity):`). Use a short, lowercase area name when it adds clarity.
- **Description** is a short, imperative-mood summary ("add", not "added"/"adds"), lowercase, no trailing period, ideally ≤ 72 characters.
- **Body** (optional) explains the *what* and *why*, not the *how*. Separate it from the description with one blank line.
- **Breaking changes** are indicated with a `!` before the colon (e.g. `feat!:`) and/or a `BREAKING CHANGE:` footer describing the change.
- Reference issues/PRs in the footer where relevant (e.g. `Closes #123`).

**Examples:**

```
feat(identity): add bulk user offboarding endpoint
fix(graph): handle expired token on retry
docs: update authentication model overview
refactor(standards)!: rename remediation parameter
```

## HTTP endpoint status codes

Endpoints in `backend/Modules/CIPPHTTP` must return a status code that matches what happened. The full guide is
`.github/agents/CIPP-Endpoint-Agent.md`.

- `200` success, `400` invalid input or refused request, `404` named resource missing, `403` CIPP access check only,
  `500` upstream (Graph/Exchange/SharePoint/Azure/table) or unexpected failure.
- Multi-item endpoints: `$StatusCode = Get-CippBulkStatusCode -Total $Total -Failed $Failed` (200 / 207 / 500).
- A `catch` never returns `[HttpStatusCode]::OK`. Use `$StatusCode = Get-CippErrorStatusCode -ErrorRecord $_`, which
  maps `ArgumentException` to 400, `ItemNotFoundException` to 404 and anything else to 500.
- Validate input before the `try`, as an `if` that returns `BadRequest`, so it can't be mistaken for an upstream failure.
- Helpers throw `[System.ArgumentException]` / `[System.Management.Automation.ItemNotFoundException]` for input and
  not-found errors, and return per-item `@{ resultText; state }` results rather than swallowing failures into strings.

## Storing tenant references

A tenant's default domain can change (`contoso.onmicrosoft.com` becomes `contoso.com`); its `customerId` cannot.
Anything that persists a tenant (table keys and columns, saved settings, JSON stored for later) stores the `customerId`.

- Resolve stored values through `Get-CIPPTenantLookup`, built once per call. It maps `customerId`, default domain and
  initial domain to the tenant, so values saved as a domain before this rule still resolve. Use the tenant's current
  `defaultDomainName` for Graph calls, logs and display.
- Match stored values on the tenant, never on the raw string: existing rows may still hold a domain.
- Don't call `Get-Tenants -TenantFilter` once per stored value. An unknown value sends it down its refresh path.
- Results rebuilt on every run (report caches, baseline alignment rows) can stay keyed by the current default domain.

## Cached list reads

AllTenants List reads come from the reporting database (`Get-CIPP<X>Report`, paged through `Get-CIPPReportPage`) or
the graph request cache (`Get-GraphRequestList -TenantFilter 'AllTenants'`). Full guide: "Cached list reads" in
`.github/agents/CIPP-Endpoint-Agent.md`.

- Paging is opt-in with `manualPagination`; without it a report-backed endpoint returns the whole report as an array.
- Never add a cache table that writes new random RowKeys on each refresh and is read whole, then filtered by
  `Timestamp` in PowerShell. It grows without bound.
- Frontend pages use `useCippReportDB({ serverPagination: true })` and pass its `resolvedApiData` and `apiDataKey`.

## PowerShell hot paths

Code that runs per row or per batch (cache collectors, `Push-*` activities, post-execution, report folds, alerts and
in-app tests) runs for every tenant, and tenants with 50k users or 20k mailboxes are normal. The runtime will not fix
churn; these patterns do.

- Filter with `foreach` + `if` or `.Where({ })`, never `| Where-Object`. Build a lookup once (hashtable, `HashSet`,
  `[CIPP.CippIndex]`, whose `.First($Key)` replaces `.Find($Key) | Select-Object -First 1`) instead of scanning inside a loop. `.Where()` returns a collection even for zero or one match;
  `.github/agents/CIPP-Test-Agent.md` lists the cases where that differs from the pipeline result.
- No `| Select-Object -First` on a hot path: it throws to stop the pipeline (`Get-Thing | Select-Object -First 1` stops
  `Get-Thing` with an exception on every call). Use `$X.Where({ P }, 'First')[0]` or `@($X)[0]`; indexing an empty
  collection also throws internally, so where it is usually empty use `foreach ($Item in $X) { $First = $Item; break }`.
- Clamp range slices: `$X[$i..([Math]::Min($i + 19, $X.Count - 1))]`. An index past the end throws and is caught
  internally, so `$X[$i..($i + 19)]` over 3 items costs 17 exceptions.
- A per-call helper that every request, standard or test hits (tenant lookups, capabilities, tokens) must not re-read a
  table and re-parse JSON each time: keep a short-lived per-tenant result (see `Get-CIPPTenantCapabilities`).
- Never `+=`. Never `Select-Object` / `Sort-Object` / `Group-Object` over hashtables.
- Never invoke a script block per row or per field (`& $Helper $Value`): each call builds a command processor and binds
  parameters (Add-CIPPDbItem's shape sampling spent 400 MB per cache run this way). Inline the loop, or move the logic
  into CIPPSharp when it is called per field.
- On a dictionary whose keys come from data, use `$Dict.PSBase.Count` / `$Dict.PSBase.Keys`: PowerShell member access
  prefers keys, so a field named `count` or `keys` silently replaces `.Count` / `.Keys`.
- Serialise with `[CIPP.CippJson]::ToJson($X, $Depth)` and fall back to `ConvertTo-Json` when it returns `$null`. Parse
  with `[CIPP.CippJson]::ConvertFromJson($Json)`, passing a field list when only some fields are read. Parse a
  `CIPPRestClient` result with `[CIPP.CippJson]::ConvertFromResponse($Result)`: it reads the UTF-8 body bytes
  (`$Result.ContentBytes`) without building `$Result.Content`, which is decoded only when something reads it. Test for a
  body with `$Result.HasContent`, not `[string]::IsNullOrWhiteSpace($Result.Content)`.
- Read an environment variable that may be unset with `[System.Environment]::GetEnvironmentVariable('Name')`: `$env:Name`
  throws and catches an exception internally every time the variable is missing.
- Don't `Add-Member -NotePropertyName` per row (it throws internally while binding its parameters):
  `$Row.PSObject.Properties.Add([psnoteproperty]::new('Name', $Value))`. `Add-Member -Force` is `$P.Remove('Name')`
  followed by that `Add` (the property moves to the end, as with `-Force`). Test for a property with
  `$null -ne $Row.PSObject.Properties['Name']`, not `$Row.PSObject.Properties.Name -contains 'Name'` (a full walk).
- Don't enumerate `.PSObject.Properties` / `.PSObject.Members` per row to read fields: it builds member sets and leaves
  them attached to every row. In CIPPSharp C#, read a row's fields with `PSMembers.InstanceProperties` (it skips hidden
  members: once anything has enumerated `Properties`, the reserved `pstypenames` sits among the instance members).
- A Pester test whose code under test uses a `[CIPP.*]` type must `Add-Type` `Shared/CIPPSharp/bin/CIPPSharp.dll` in
  `BeforeAll`; helpers that fall back when the type is missing otherwise pass while testing the wrong path.

## Helper functions

Every function is one more place a contributor has to look, so a new one has to earn its place.

- Write logic that has one caller inline where it is used. Add a function only when it has two or more real callers, or
  it is a generic building block like the Graph, Exchange, table and tenant helpers in `CIPPCore/Public/GraphHelper`.
- Don't wrap a single call to an existing function (a new function whose body is one `Start-CIPPOrchestrator` call):
  call the existing function directly.
- Don't declare functions inside functions. Put the branch inline, or compute the input first and classify it once.
- Search for an existing helper before writing one, and extend it rather than adding a near-copy.
