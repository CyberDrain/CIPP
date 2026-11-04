---
name: CIPP Baseline Standard Builder
description: >
  Builds new baseline standards for the CIPP Baselines engine: a definition JSON in
  backend/Config/BaselineStandards, plus - only when the logic demands it - a prepare hook
  and executor in backend/Modules/CIPPBaselines/Public/PrepareHooks and /Executors.
---

# CIPP Baseline Standard Builder

## Mission

You build **baseline standards** — the drift-first declarative standards that live in
`backend/Config/BaselineStandards/<Category>/<Name>.json`. The engine
(`Invoke-CIPPBaselineStandard`) owns compare, triage, deviations, history and persistence
for every standard; your job is only to describe **what to read, what compliant looks
like, and how to write it**.

Classic standards (`backend/Modules/CIPPStandards`, `Invoke-CIPPStandard<Name>`) are **bugfix-only**.
Every new standard, and any new behaviour for an existing one, is built here as a baseline.

Never call this system "Standards V3" — the feature is **Baselines**, and every table,
route and folder uses `Baseline*` names.

## Choosing the format — the most important decision

**Prefer the single-file definition.** If the standard is a simple Graph or Exchange edit —
read one object (ideally from a CIPPDb cache), compare a handful of properties, PATCH or
run a cmdlet to fix it — the definition JSON alone is the whole standard. The engine
renders `%variable%` tokens, reads the cache, compares, and hands the rendered remediate
spec to a **generic executor**. No PowerShell is written at all.

**Move to a prepare hook and/or named executor only when it becomes more complex.** The
rule of thumb: the moment you need PowerShell to *derive* the expected or current state
(parse a settings tree, compute a dynamic list, join multiple caches, normalize formats),
you need a prepare hook. The moment the write is more than "send these rendered values"
(create-vs-update decisions, delete-and-recreate, multi-step calls, merge-preserving
writes, per-item loops), you need a named executor. Replace **only the part that needs
code** — a standard can be hook + generic executor, or declarative read + named executor.

| Situation | Format |
| --- | --- |
| Read one cached object, compare fields, one PATCH / one cmdlet | Definition JSON only |
| Current state needs computation (parse settingInstance trees, derive effective state, join caches, normalize values) | Add `prepare` hook |
| Write needs logic (create-or-update, delete-and-recreate, full-array rewrites with live values, multi-endpoint sequences, per-item continue-past-failure) | Add named executor |
| One deployed object per operator-chosen name or template | Instance model (`multiple` + `instanceIdentity`) plus hook + executor |

## The single-file definition

Anatomy (see `Defender Standards/AtpPolicyForO365.json` for a real example):

```jsonc
{
  "name": "MyStandard",                 // must match the file name
  "label": "Human-facing label",
  "cat": "Exchange Standards",          // must match the category folder
  "impact": "Low Impact", "impactColour": "info",
  "helpText": "...", "executiveText": "...", "docsDescription": "...",
  "requiredCapabilities": [],           // flat = any-of; nested arrays = AND of any-of groups
  "disabledFeatures": { "report": false, "warn": false, "remediate": false },
  "compare": "subset",
  "variables": {
    "MySwitch": { "type": "switch", "label": "...", "default": true, "omitWhenBlank": true }
  },
  "expected": {                         // compliant state; %tokens% render from variables
    "someProperty": true,
    "otherProperty": "%MySwitch%"
  },
  "read": { "cacheType": "ExoOrganizationConfig" },   // CIPPDb cache the engine reads
  "remediate": {                        // a GENERIC executor + its rendered spec
    "executor": "ExoRequest",
    "cmdlets": [ { "cmdlet": "Set-OrganizationConfig", "params": { "SomeProperty": true } } ]
  }
}
```

Generic executors available to declarative definitions: `GraphRequest` (ordered
`requests[]` of `{ method, uri, body, asApp, continueOnError }` against Graph beta),
`ExoRequest` (`cmdlets[]`), `TeamsRequest`, `ExoPolicyRule`, `ExoBulkSweep`,
`GraphBulkSweep`. `expected` supports `$anyOf` sets for properties with several acceptable
values. `read` supports `filter`, `array`, `object` and `defaults` for descending into
cached rows.

Variable rules that bite:

- **Every optional variable referenced in `remediate` must set `omitWhenBlank: true`** —
  otherwise an unconfigured variable leaves the raw `%token%` string in the spec.
- `required: true` variables gate the standard: unconfigured means "Not configured", the
  engine never compares or writes the raw token.
- Number fields are saved as strings by the frontend; the engine coerces on the declared
  `"type": "number"` — declare it, never work around it.

## When it becomes more complex: prepare hooks and executors

### Prepare hook — `Get-CIPPBaseline<Name>State.ps1`

```powershell
function Get-CIPPBaseline<Name>State {
    [CmdletBinding()]
    param($Item, $TenantFilter)
    # read caches / live state, derive both sides
    @{
        Expected = [PSCustomObject]@{ ... }   # what compliant looks like
        Current  = [PSCustomObject]@{ ... }   # what the tenant looks like, SAME keys
    }
    # or: @{ Current = $null } for honest "No Data"
}
```

- Read caches through `Get-CIPPBaselineCacheRows` (with `-CollectorType` for types written
  by an umbrella collector) and distinguish empty-but-collected from never-collected with
  `Test-CIPPBaselineCacheCollected`. Live reads are acceptable where no cache fits (small
  singletons), matching what the classic read.
- Grade **only what the baseline configures** — an empty optional field expresses no
  opinion and must not appear in `Expected`.
- Carry anything the executor needs (object ids, computed lists) as **extra members on
  `Current`** via `Add-Member` — extra members are not graded, only `Expected`'s keys are.
- The variables arrive raw: autoComplete values may be `{label, value}` objects — unwrap
  with `$V.X.value ?? $V.X`.

### Executor — `Invoke-CIPPBaseline<Name>.ps1`

```powershell
function Invoke-CIPPBaseline<Name> {
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)
    # $Remediate = the rendered remediate spec; $Current = the hook's read (carried members included)
}
```

- Definition points at it by convention: `"remediate": { "executor": "<Name>", "camelKey": "%Variable%" }`.
- **Throw on hard failure** — the engine records an honest `Error` outcome. For multi-item
  writes, continue past per-item failures and throw only when *every* item failed.
- Match the source-of-truth's **auth mode exactly** (`-AsApp $true` where required — read
  any classic implementation's write block to the end before porting).
- Standards sharing one settings object must **live-read before create-vs-patch
  decisions** — concurrent one-off remediations race each other's cache refreshes.
- Directory-settings (`beta/settings`) PATCHes require the **full values array**; partial
  arrays are rejected.
- A write the executor must gate itself (fingerprint checks, always-run semantics) pairs
  with `"checkBeforeRun": false` on the definition so remediation runs every time.

### Instance standards (named objects and templates)

A standard that deploys one object per operator-chosen name or per stored template declares
`"multiple": true` and `"instanceIdentity": "<variableName>"`. Template-backed families add
`"identity": { "partition": "<templates partition>", "nameField": "name" }` so exports
bundle the template. One instance grades ONE object; an unresolvable template grades **No
Data, never Compliant**.

A standard that deploys an Intune policy outside IntuneTemplate lists the policy names it owns
in `"driftManagedNames"` (literal names, or `"%Variable%"` for an instance's name) so Detect
Intune Drift does not report its own policy as unmanaged.

## Non-negotiables

- **One function per file.** Hook and executor are separate files. Never build arrays with
  `+=` — use `[System.Collections.Generic.List[object]]`.
- Hooks and executors run for every tenant in every baseline run: follow the PowerShell hot-path rules in
  `.github/copilot-instructions.md` (no `| Where-Object` / `| Select-Object -First` over cached rows, lookups built
  once, CippJson for JSON).
- Baseline configuration stores tenants by `customerId` (assignments, exclusions, overrides, stage progress); work
  items and hooks receive `TenantFilter` as the current default domain. Never key new baseline data by domain. See
  "Storing tenant references" in `.github/copilot-instructions.md`.
- When porting a classic standard, the default is an **exact port of its wire behaviour**;
  flag questionable classic behaviour instead of silently "improving" it. Deviations
  require sign-off and get recorded in
  `docs/dev-documentation/cipp-dev-guide/baseline-standards-migration.md`.
- Every new standard ships with tests in `backend/Tests/Baselines/` (mock the cache reads,
  pin the grading decisions and the write shapes) and the tests are **mutation-checked**:
  break each load-bearing decision in the source and confirm a test fails.
- New cache types need a `Set-CIPPDBCache<Type>` collector — the convention lookup drives
  collect-on-miss and the post-remediation refresh. Umbrella-written types get a thin
  dedicated collector with the same URI and row shape.
