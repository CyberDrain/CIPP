All repository guidance is in [`AGENTS.md`](../AGENTS.md) at the repository root: architecture, conventions, commit
messages, status codes, tenant references, cached list reads, helper functions and the PowerShell performance rules.
Task-specific guides are in `.github/agents/`.

The rules most often missed in review:

- Conventional Commits (`feat(identity): add bulk user offboarding endpoint`); PRs target `dev`.
- A `catch` never returns `200`: `$StatusCode = Get-CippErrorStatusCode -ErrorRecord $_`.
- Persist tenants by `customerId`, never by domain.
- Never `+=`, never `| Where-Object` or `| Select-Object -First` on per-row code, never a scan inside a loop (build a
  hashtable once), never `Select/Sort/Group-Object` over hashtables.
- A new function needs two or more real callers.
