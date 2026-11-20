# Contributing to the Code

Contributions to CIPP are welcome. The entire project, frontend and backend, lives in a single mono-repository: [CyberDrain/CIPP](https://github.com/CyberDrain/CIPP). The old separate CIPP and CIPP-API repositories are deprecated.

Before writing any code, set up a local development environment by following the guide in [setting-up-for-local-development.md](cipp-dev-guide/setting-up-for-local-development.md "mention").

## Before You Start

- **File an issue.** If you are fixing a bug, file a complete bug report [on GitHub](https://github.com/CyberDrain/CIPP/issues) and assign it to yourself. If you are adding a feature, create an issue with "Feature Request" in the title and assign it to yourself.
- **Understand the repo layout.** Read the [project-structure.md](cipp-dev-guide/project-structure.md "mention") page so you know where frontend pages, backend modules, and tests live.
- **Speed and security** are fundamental pillars of CIPP. If it is not fast, it is not good, and if it is not secure, it is not getting merged.
- **Read [`AGENTS.md`](https://github.com/CyberDrain/CIPP/blob/dev/AGENTS.md)** at the repository root. It is the guide for both people and AI coding assistants: architecture, conventions and the PowerShell performance rules every change is reviewed against. Task-specific guides for endpoints, baselines, alerts and tests are in [`.github/agents/`](https://github.com/CyberDrain/CIPP/tree/dev/.github/agents).
- **Use native APIs over PowerShell modules.** PowerShell modules slow the entire runtime. The backend currently loads only `Az.Keyvault` and `Az.Accounts` and we prefer to keep it that way.

{% hint style="info" %}
You can assign yourself an issue on GitHub by commenting `I would like to work on this please!` on the issue. You must enter that text verbatim.
{% endhint %}

## Pull Requests

- All pull requests target the **`dev`** branch. The `main` branch is the current release and does not accept direct PRs.
- Use a [Conventional Commits](https://www.conventionalcommits.org/) title, for example `feat(identity): add bulk user offboarding endpoint` or `fix(graph): handle expired token on retry`.
- Keep pull requests focused. A bug fix and a new feature belong in separate PRs.
- When your change alters what a user sees or can do (new fields, columns, buttons, renamed labels, new behaviour), update the matching documentation page in the same PR. See [contributing-to-the-documentation.md](contributing-to-the-documentation.md "mention") for the style guide.

## Function Naming

Every HTTP endpoint handler in `backend/Modules/CIPPHTTP/` must use one of these prefixes:

| Prefix           | Purpose                                         | Example               |
| ---------------- | ----------------------------------------------- | --------------------- |
| `Invoke-List*`   | Returns a list or read-only data (GET)          | `Invoke-ListUsers`    |
| `Invoke-Add*`    | Creates a new object                            | `Invoke-AddUser`      |
| `Invoke-Edit*`   | Modifies an existing object                     | `Invoke-EditUser`     |
| `Invoke-Remove*` | Deletes or removes an object                    | `Invoke-RemoveUser`   |
| `Invoke-Exec*`   | Executes an action (for example, send MFA push) | `Invoke-ExecSendPush` |

The HTTP router in CIPPCore maps the `CIPPEndpoint` route parameter to `Invoke-{CIPPEndpoint}`, so the function name is exactly what appears in the URL.

## Backend Guidelines

- **Always pass `-tenantid`** to `New-GraphGetRequest`, `New-GraphPOSTRequest`, `New-GraphBulkRequest`, and `New-ExoRequest`. Omitting it hits the partner tenant instead of the customer.
- Backend modules under `backend/Modules/` are **ModuleBuilder-compiled**. Editing a source file does nothing until it is recompiled. The module watcher handles this automatically during local development; see the [setting-up-for-local-development.md](cipp-dev-guide/setting-up-for-local-development.md "mention") page for details.
- Run the relevant **Pester tests** before submitting:

```powershell
pwsh -File backend/Tests/Invoke-CippTests.ps1                                # all tests
pwsh -File backend/Tests/Invoke-CippTests.ps1 -Path backend/Tests/Standards  # one area
```

### Status Codes

Return a status code that matches what happened. The frontend decides whether to retry or how to render a response from its status code, the MCP integration treats `400` and above as an error, and successful `GET` responses are cached. A failure returned as `200` is shown and cached as if it were data.

| Situation                                                                       | Status code |
| ------------------------------------------------------------------------------- | ----------- |
| Success                                                                         | `200`       |
| Missing or invalid input, or a request the business rules refuse                | `400`       |
| A resource the caller named does not exist                                      | `404`       |
| A CIPP access check refuses the caller                                          | `403`       |
| A Microsoft Graph, Exchange, SharePoint, Azure or storage call failed           | `500`       |
| Several items processed: all succeeded / some failed / all failed               | `200` / `207` / `500` |

- Validate input before the `try` block and return `400` straight away.
- In a `catch` block, set the status with `Get-CippErrorStatusCode -ErrorRecord $_`. A `catch` block must never return `200`; the `backend/Tests/Static` tests enforce this.
- For endpoints that act on several items, set the status with `Get-CippBulkStatusCode -Total $Total -Failed $Failed`.
- Helper functions throw `[System.ArgumentException]` for invalid input and `[System.Management.Automation.ItemNotFoundException]` for missing resources, so the endpoint can tell those apart from upstream failures.

The full guide, including response body shapes, is in [`.github/agents/CIPP-Endpoint-Agent.md`](https://github.com/CyberDrain/CIPP/blob/dev/.github/agents/CIPP-Endpoint-Agent.md).

### Performance

Backend code that runs per row or per tenant (cache collectors, alerts, tests, baselines, reports) runs for every managed tenant, and tenants with 50,000 users are normal. Pull requests are reviewed against these requirements:

1. No `| Where-Object`, `| Select-Object -First`, `| ForEach-Object` or `& $ScriptBlock` per row. Use `foreach` with `if`, or `.Where({ })`.
2. No search of one list inside a loop over another. Build a hashtable (or `[CIPP.CippIndex]`) once, keyed on an id, GUID or UPN.
3. No `+=`. Assign the output of a `foreach`, or use `[System.Collections.Generic.List[object]]`.
4. No per-row `Add-Member`. Use `$Row.PSObject.Properties.Add([psnoteproperty]::new('Name', $Value))`.
5. JSON through `[CIPP.CippJson]::ToJson` / `ConvertFromJson`, not `ConvertTo-Json` / `ConvertFrom-Json`.
6. Large reads stream into the cache (`New-GraphGetRequest -Stream`, `New-ExoRequest -StreamPages`) instead of holding a whole tenant in memory.
7. Table reads filter on `PartitionKey` (and `RowKey` for one row), and a `-Property` list always includes `PartitionKey` and `RowKey`.
8. Graph and Exchange calls are batched (`New-GraphBulkRequest`, `New-ExoBulkRequest`) and `$select` only the fields the code reads.
9. A performance change states its before and after numbers from a realistic tenant, and produces identical output.

For example, finding each user's groups:

```powershell
# Before: searches every group once per user, and += copies the array each time
$Result = @()
foreach ($User in $Users) {
    $Groups = $AllGroups | Where-Object { $_.members.id -contains $User.id }
    $Result += [PSCustomObject]@{ UPN = $User.userPrincipalName; Groups = $Groups.displayName -join ', ' }
}

# After: one pass to build a user -> groups lookup, one pass to emit rows
$GroupsByUser = @{}
foreach ($Group in $AllGroups) {
    foreach ($Member in $Group.members) {
        if (-not $GroupsByUser[$Member.id]) { $GroupsByUser[$Member.id] = [System.Collections.Generic.List[string]]::new() }
        $GroupsByUser[$Member.id].Add($Group.displayName)
    }
}
$Result = foreach ($User in $Users) {
    [PSCustomObject]@{ UPN = $User.userPrincipalName; Groups = @($GroupsByUser[$User.id]) -join ', ' }
}
```

With 2,000 users and 200 groups the first version takes about 5.5 seconds and the second about 0.15 seconds, with identical output. The full list, with measurements and the traps that make a faster rewrite return different results, is the performance section of [`AGENTS.md`](https://github.com/CyberDrain/CIPP/blob/dev/AGENTS.md).

### Design Requirements

- **Read the cache first.** Reports, cached list pages, tests and baselines read the CIPP reporting cache rather than calling Microsoft 365 live for every item. If a report needs data the cache lacks, extend the collector that fills it.
- **New standards are Baselines.** Classic standards in `CIPPStandards` accept bug fixes only.
- **Write PowerShell.** Contributors must be able to read and fix the code, so purpose-built C# is not accepted; the existing generic helpers in `backend/Shared/CIPPSharp` are fine.
- **Keep one code path.** No fallback branches that detect a problem and quietly degrade.
- **Store tenants by `customerId`**, never by domain name, because a tenant's default domain can change.
- **Keep it working on Azure Functions.** The new CIPP infrastructure runs .NET 10 and PowerShell 7.6, but self-hosted Function App installs still run this backend on PowerShell 7.4 (.NET 8). Code must work on both, which is why `CIPPSharp` targets .NET 8.
- **Write functions only when they are reused.** Logic with one caller stays inline.

## Frontend Guidelines

- See [frontend-testing.md](cipp-dev-guide/frontend-testing.md "mention") for test conventions and how to run the test suites.
- Remember to lint your code with prettier, as to not cause another war of formatters.
- On a page that uses the selected tenant, put the tenant in every query key, so switching tenants never shows the previous tenant's data.
- Run API actions through `CippApiDialog` (confirm, then show the results inline), not toast pop-ups.
- Import icons only from `src/utils/icon-registry.jsx`.
- Write labels, statuses and errors for MSP technicians in plain English, and say what to do about each error.

## Documentation

If your change adds, removes, or renames anything a user can see in the interface, update the documentation in the same pull request. User-facing docs live under `docs/` and mirror the frontend route path. The full style guide and submission process are in [contributing-to-the-documentation.md](contributing-to-the-documentation.md "mention").
