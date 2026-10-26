---
name: CIPP Compliance Test Builder
description: >
  Adds or changes the in-app compliance tests in backend/Modules/CIPPTests (CIS / CISA / E8 / EIDSCA / ORCA / ZTNA /
  SMB1001 / CopilotReadiness / GenericTests / SecuritySimulations): Invoke-CippTest<Id> functions that read the tenant's
  cached data and record a verdict.
---

# CIPP Compliance Test Builder

## Mission

Write or change a test so that it:

- reads only cached data through `Get-CIPPTestData`, with the fields it reads listed in the field manifest,
- records exactly one verdict per run through `Add-CippTestResult`,
- costs time and memory in proportion to the tenant, not to the tenant squared. A suite runs for every tenant, and
  tenants with 50k users / 20k mailboxes are normal.

These are not unit tests. Pester tests live in `backend/Tests/` (see the end of this file).

---

## Anatomy

```powershell
function Invoke-CippTestEIDSCAAP01 {
    <#
    .SYNOPSIS
    Authorization Policy - Self-Service Password Reset for Admins
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'
        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database.' -Risk 'High' -Name '...' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }
        $Status = if ($AuthorizationPolicy.allowedToUseSSPR -eq $false) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name '...' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name '...' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
```

- One file per test: `CIPPTests/Public/Tests/<Suite>/<Area>/Invoke-CippTest<Id>.ps1`, with a matching `.md` beside it
  (the remediation text shown in the UI).
- Suite membership is by name pattern (`Get-CippTestSuitePatterns`), not folder. The TestId is the function name
  without `Invoke-CippTest`.
- Work several tests share per tenant (one Graph call, one grading pass) goes in `Initialize-CippTestSuite<Suite>`,
  which `Invoke-CIPPTestCollection` runs before the suite, with a matching `Clear-CippTestSuite<Suite>` after it.

---

## Reading data

- **Only through `Get-CIPPTestData -TenantFilter $Tenant -Type '<Type>'`.** It is cached process-wide for the run
  (`[CIPP.TestDataCache]`, shared by every worker), so the same type is parsed once per tenant, not once per test.
- **Records are field-projected.** Only the fields listed for the type in `Get-CippTestDataFieldManifest` exist on the
  record. Reading an unlisted field returns `$null` with no error and a silently wrong verdict. Add the field to the
  manifest before you read it. A kept field keeps its whole subtree (`conditions` covers `conditions.users.includeRoles`).
  Use `ListDBCache` to confirm a field's real name and casing.
- **Do not pass `-Fields` from a test.** Field lists belong to the type; per-call lists fragment the cache (the same rows
  parsed once per list).
- Records are `PSCustomObject` and stay that way: `$x[0]`, `$x.Count` and `.PSObject.Properties` rely on it.
- A missing type returns nothing: emit `Skipped` with a reason, never `Passed`.

---

## Filtering without pipelines

A pipeline costs a command processor and parameter binding per item; `| Select-Object -First` also throws two
exceptions every time it stops the pipeline. Do not write `| Where-Object` or `| Select-Object -First` in a test.

| Instead of | Write |
| --- | --- |
| `@($X \| Where-Object { P })` | `@($X.Where({ P }))` |
| `($X \| Where-Object { P }).Count` | `$X.Where({ P }).Count` |
| `$X \| Where-Object { P } \| Select-Object -First 1` | `$X.Where({ P }, 'First')[0]` |
| `$X \| Select-Object -First 1` (variable or member chain) | `@($X)[0]` |
| `$X \| Select-Object -First 50` used by a `foreach` | `$X.Where({ $true }, 'First', 50)` |
| a scan inside a per-user loop | a hashtable / `HashSet` / `[CIPP.CippIndex]` built once before the loop |

Call `.Where` straight on a variable or member chain (`$Cfg.authenticationMethodConfigurations.Where(...)`); wrap
anything else in parentheses (`(Get-Thing).Where(...)`).

`.Where()` always returns a collection, even for zero or one match. That is identical to the pipeline result for
`if ($x)`, `-not $x`, `.Count`, `@($x)`, `foreach`, piping on, `-contains` / `-in`, `-join` and `"$x"`. It is NOT
identical for:

- `$null -eq $x` / `$x -eq $null`: an empty collection is not `$null`;
- `$x + $y` / `@('a') + $x`: an empty collection adds nothing where `$null` adds one element, and a collection has no
  `op_Addition`;
- storing `$x` in a result object or anything serialised: ConvertTo-Json writes a one-item collection as an array;
- `$x[0]` when the single match is a string (pipeline: first character);
- `$x.Prop` when the single match's `Prop` is a one-element or empty array (member access unrolls it);
- a source that can itself be a single `$null`, with a predicate that is true for `$null`: the pipeline emits `$null`
  once, `.Where` emits nothing.

In those cases keep scalar semantics with a `foreach` statement, whose assigned result is `$null`, the item, or an
array exactly like the pipeline: `$x = foreach ($Item in $X) { if (P) { $Item } }` (rename the top-level `$_` only).
That form flattens an item that is itself a collection, so use it only for records and strings.

---

## Other hot-path rules

The repo-wide list is in `.github/copilot-instructions.md` (PowerShell hot paths). The ones tests hit most:

- Never `+=`. Build with `@(...)`, a `foreach` assignment or `[System.Collections.Generic.List[object]]`.
- Never `Select/Sort/Group-Object` over hashtables.
- `[CIPP.CippJson]::ToJson($x, $depth)` (fall back to `ConvertTo-Json` on `$null`) for result data JSON.
- No `ConvertTo-Json` inside log or markdown strings that are built whether or not they are used.

---

## Verifying a change

"0 errored" proves nothing: every failure mode here is a silent wrong verdict.

1. Capture verdicts (status + markdown + result data) for every suite on a real tenant before and after the change, and
   diff them. Normalise run-varying text (timings, `lastRun`, row and key order) before comparing.
2. Take the baseline against the same cached data as the change. A cache collection between the two runs changes data
   and shows up as verdict differences that are not yours.
3. Use more than one tenant when a rule depends on exactly one matching record.
4. Run an end-to-end tests run in Craft as well when the change touches anything that writes rows (cache helpers,
   `Add-CIPPDbItem`, CippJson): the in-process verdict diff never writes, so it cannot see a row that fails to read back.

---

## Pester

- Tests for test functions go in `backend/Tests/CippTests/`: dot-source the test, define `Get-CIPPTestData` and
  `Add-CippTestResult` stubs that return fixtures / capture the result, and assert the verdict.
- Any Pester file whose code under test uses a `[CIPP.*]` type must load the DLL in `BeforeAll`:
  `Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')`. Several helpers fall back silently when the
  type is missing, so without it the test exercises the wrong path. `backend/Tests/New-CippTest.ps1` adds the line when
  it sees a `[CIPP.*]` type.
