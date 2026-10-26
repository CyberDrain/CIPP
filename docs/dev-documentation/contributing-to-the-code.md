# Contributing to the Code

Contributions to CIPP are welcome. The entire project, frontend and backend, lives in a single mono-repository: [CyberDrain/CIPP](https://github.com/CyberDrain/CIPP). The old separate CIPP and CIPP-API repositories are deprecated.

Before writing any code, set up a local development environment by following the guide in [setting-up-for-local-development.md](cipp-dev-guide/setting-up-for-local-development.md "mention").

## Before You Start

- **File an issue.** If you are fixing a bug, file a complete bug report [on GitHub](https://github.com/CyberDrain/CIPP/issues) and assign it to yourself. If you are adding a feature, create an issue with "Feature Request" in the title and assign it to yourself.
- **Understand the repo layout.** Read the [project-structure.md](cipp-dev-guide/project-structure.md "mention") page so you know where frontend pages, backend modules, and tests live.
- **Speed and security** are fundamental pillars of CIPP. If it is not fast, it is not good, and if it is not secure, it is not getting merged.
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

## Frontend Guidelines

- See [frontend-testing.md](cipp-dev-guide/frontend-testing.md "mention") for test conventions and how to run the test suites.
- Remember to lint your code with prettier, as to not cause another war of formatters.

## Documentation

If your change adds, removes, or renames anything a user can see in the interface, update the documentation in the same pull request. User-facing docs live under `docs/` and mirror the frontend route path. The full style guide and submission process are in [contributing-to-the-documentation.md](contributing-to-the-documentation.md "mention").
