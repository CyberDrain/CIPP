---
name: CIPP Alert Builder
description: >
  Adds or changes scripted alerts in backend/Modules/CIPPAlerts (Get-CIPPAlert<Name>.ps1): per-tenant checks that
  report what they find through Write-AlertTrace. The frontend entry is a separate job for CIPP-Frontend-Alert-Agent.md.
---

# CIPP Alert Builder

## Mission

Write or change an alert so that it:

- reports everything it finds for one tenant in a single `Write-AlertTrace` call, including an empty result,
- never reports "clear" when it could not check,
- costs time and memory in proportion to the tenant. Alerts run on a schedule for every tenant, and tenants with 50k
  users or 20k mailboxes are normal.

---

## Anatomy

```powershell
function Get-CIPPAlertThing {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$select=id,userPrincipalName,accountEnabled' -tenantid $TenantFilter
        $AlertData = foreach ($User in $Users) {
            if ($User.accountEnabled) { continue }
            [PSCustomObject]@{
                UserPrincipalName = $User.userPrincipalName
                Id                = $User.id
                Message           = 'User {0} is disabled' -f $User.userPrincipalName
                Tenant            = $TenantFilter
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to check things for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
```

- File: `CIPPAlerts/Public/Alerts/Get-CIPPAlert<Name>.ps1`. It also needs an entry in `frontend/src/data/alerts.json`
  (`CIPP-Frontend-Alert-Agent.md`) to be selectable in the UI; `inputName` there is the property read from `$InputValue`.
- `$InputValue` is the alert's configuration: a scalar for single-input alerts, an object for multi-input ones. Keep
  reading the legacy scalar form when you add fields.

---

## Reporting

- **Call `Write-AlertTrace` once per run with the full result**, also when it is empty: an empty run resolves whatever
  was still open. Use `-Append` only for event-stream alerts that see a slice, not the whole picture.
- **Do not call it when the check failed part-way.** "Could not check" is not "clear"; it would resolve open alerts.
  Log the failure instead.
- **Items need a stable identity.** `Get-AlertContentHash` keys an item on `UserPrincipalName`, then `Id`, then
  `Message`, and otherwise on the whole item. Include one of those, so a changing value (a day count, a timestamp) does
  not turn the same finding into a new alert on every run.
- Only New and Reopened items notify; snoozes are handled for you.

---

## Data and performance

- Prefer the cache when it holds what you need (`New-CIPPDbRequest -TenantFilter $TenantFilter -Type '<Type>'`, with a
  field list when you read a few fields); call Graph or Exchange live only for data that must be current.
- `$select` only the fields you read, and filter server-side when Graph supports it.
- Follow the hot-path rules in `.github/copilot-instructions.md`. For alerts that means above all: no
  `New-GraphGetRequest ... | Where-Object` over a whole user or mailbox list (a `foreach` with `if`/`continue`), and no
  scan of one list inside a loop over another (build a hashtable keyed on the join field first).

---

## Tests

- `backend/Tests/Alerts/`: stub the Graph/cache reads and `Write-AlertTrace`, then assert the items passed to
  `-data`, an empty run, and that a failed read does not call `Write-AlertTrace`.
- Load `Shared/CIPPSharp/bin/CIPPSharp.dll` in `BeforeAll` when the alert uses a `[CIPP.*]` type.
