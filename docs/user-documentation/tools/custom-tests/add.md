# Add/Edit Custom Test

This page creates a new custom test and is also where existing tests are edited. Opening it from **Add Test** gives you a blank form; opening it through **Edit Test** on an existing test loads that test's current version, and saving creates a new version rather than overwriting the old one.

{% hint style="danger" %}
Custom tests are read-only. A test cannot write to CIPP's tables or make any change in the client tenant.
{% endhint %}

The page is arranged as four collapsible sections. **Test Guidance** and **Test Script Output** open by default when adding a test and editing one respectively.

## Test Guidance

Reference material for writing the script, worth reading before your first test. It covers how a result status is decided, the constraints the script runs under, and the data available to it. **Example Scripts**, below, lists worked scripts you can copy as a starting point.

### How the Result Is Decided

| Outcome         | How to produce it                                                                                                                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pass            | Return `$null`, `$false`, an empty string, or `@()`.                                                                                                                                                                                  |
| Fail            | Return any non-empty value. Whatever is returned becomes the test output.                                                                                                                                                             |
| Explicit status | Return a hashtable containing `CIPPStatus` (`Passed`, `Failed`, `Info` or `Investigate`), `CIPPResults`, and optionally `CIPPResultMarkdown` to control both the status and how it renders. Only honoured when Result Mode is `Auto`. |

### Scripting Constraints

{% hint style="warning" %}
Scripts run in PowerShell **ConstrainedLanguage** mode, so only approved cmdlets are available. `New-Object`, `[pscustomobject]@{}` casts, and .NET and reflection calls are all blocked. Build rows with `Select-Object @{Name;Expression}` and return a plain `@{}` hashtable instead. If you build your own intermediate list of `@{}` hashtables, pipe it through `Select-Object -ExpandProperty` at your own risk: that specific parameter throws a hashtable-to-object conversion error under ConstrainedLanguage, even though `$_.property` on the same hashtable works. Data read back from `Get-CIPPTestData` does not hit this, since Graph-sourced records are objects rather than hashtables.
{% endhint %}

Data is read through `Get-CIPPTestData` with a `-Type` parameter. The tenant is locked automatically, so do not pass `-TenantFilter`. **View Cached Types** opens a dialog listing every available type with its description, and the eye icon beside each one shows sample data from the currently selected tenant, which is the quickest way to see the shape of what you will be working with.

Type `%` anywhere in the script to insert a replacement variable, such as `%tenantid%` or `%defaultdomain%`, alongside any custom variables you have defined.

### AI Prompt Template

Paste the block below into an AI assistant along with a description of your use case, and it has the context needed to write a compliant script.

```
Create a custom test for CIPP(https://docs.cipp.app/user-documentation/tools/custom-tests/add).

Custom tests are read-only via Get-CIPPTestData with -Type. Tenant is auto-locked — do not pass -TenantFilter. Use %variable% syntax for replacement variables.

This script is CyberDrains example for Conditional access: 
# Summarize Conditional Access policies by state
$Policies = Get-CIPPTestData -Type 'ConditionalAccessPolicies'
$grouped = $Policies | Group-Object -Property state

$counts = $grouped | Select-Object @{Name='State'; Expression={ $_.Name }},
    @{Name='Count'; Expression={ $_.Count }}

# Build markdown summary — %tenantname% is replaced at runtime
$header = "### %tenantname% — CA Policies: $(@($Policies).Count) total

| State | Count |
|---|---|"
$countRows = $counts | ForEach-Object {
    "| $($_.State) | $($_.Count) |"
}
$summaryTable = @($header) + @($countRows) -join "
"

# List each policy
$policyHeader = "| Policy | State | Created |
|---|---|---|"
$policyRows = $Policies | Sort-Object -Property state, displayName | ForEach-Object {
    "| $($_.displayName) | $($_.state) | $($_.createdDateTime) |"
}
$policyTable = @($policyHeader) + @($policyRows) -join "
"

$md = $summaryTable + "

---

" + $policyTable

@{
    CIPPStatus         = 'Passed'
    CIPPResults        = $counts
    CIPPResultMarkdown = $md
}

This is their script for Users with licenses:
# List all users and their licenses with friendly SKU names
$Users = Get-CIPPTestData -Type 'Users'
$Licenses = Get-CIPPTestData -Type 'LicenseOverview'

# Build a SKU ID -> display name lookup hashtable
$SkuLookup = @{}
$Licenses | ForEach-Object {
    $SkuLookup[$_.skuId] = $_.License
}

# Build results - users with their resolved license names
$results = $Users | Where-Object {
    $_.assignedLicenses.Count -gt 0
} | Select-Object @{Name='UserPrincipalName'; Expression={ $_.userPrincipalName }},
    @{Name='DisplayName'; Expression={ $_.displayName }},
    @{Name='AccountEnabled'; Expression={ $_.accountEnabled }},
    @{Name='LicenseCount'; Expression={ @($_.assignedLicenses).Count }},
    @{Name='Licenses'; Expression={ (@($_.assignedLicenses | ForEach-Object { $n = $SkuLookup[$_.skuId]; if ($n) { $n } else { $_.skuId } }) -join ', ') }}

# Build markdown table
$header = "### Licensed Users: $($results.Count)\n\n| User | Display Name | Enabled | Licenses |\n|---|---|---|---|"
$rows = $results | ForEach-Object {
    "| $($_.UserPrincipalName) | $($_.DisplayName) | $($_.AccountEnabled) | $($_.Licenses) |"
}
$md = @($header) + @($rows) -join "\n"

# Return with explicit pass + markdown
@{
    CIPPStatus         = 'Passed'
    CIPPResults        = $results
    CIPPResultMarkdown = $md
}


I want you to build a script that cross references all CA policies, included groups, and show me which user is missing a license for P1 functionality(conditional acccess) or P2 functionality(Risk settings in CA).
```

{% hint style="info" %}
This covers data access, but not the ConstrainedLanguage restrictions in **Scripting Constraints**, above. If an AI-written script comes back using `New-Object` or a `[pscustomobject]@{}` cast, that is why: add the ConstrainedLanguage sentence from **Scripting Constraints** to the prompt, or fix the flagged lines by hand.
{% endhint %}

### Example Scripts

Six starting points, from a straightforward filter to a multi-section markdown report. Copy one in as written or adapt it, and set Result Display Type to match: four of the six return `CIPPResultMarkdown` and render as markdown regardless of that setting, so set it to `Markdown` anyway so the field reflects what happens. The other two (Disabled Users with Active Licenses, Stale Guest Accounts) just return raw rows, so leave Result Display Type as `JSON` unless you want to build a Markdown Result Template from them after the first run.

<details>

<summary>Licensed Users with Resolved SKU Names</summary>

Lists every licensed user and resolves their assigned SKU IDs to friendly names using the licence cache, returning a markdown table with an explicit `Passed` status. Demonstrates `CIPPStatus`, `CIPPResults` and `CIPPResultMarkdown` together.

```powershell
# List all users and their licenses with friendly SKU names
$Users = Get-CIPPTestData -Type 'Users'
$Licenses = Get-CIPPTestData -Type 'LicenseOverview'

# Build a SKU ID -> display name lookup hashtable
$SkuLookup = @{}
$Licenses | ForEach-Object {
    $SkuLookup[$_.skuId] = $_.License
}

# Build results - users with their resolved license names
$results = $Users | Where-Object {
    $_.assignedLicenses.Count -gt 0
} | Select-Object @{Name='UserPrincipalName'; Expression={ $_.userPrincipalName }},
    @{Name='DisplayName'; Expression={ $_.displayName }},
    @{Name='AccountEnabled'; Expression={ $_.accountEnabled }},
    @{Name='LicenseCount'; Expression={ @($_.assignedLicenses).Count }},
    @{Name='Licenses'; Expression={ (@($_.assignedLicenses | ForEach-Object { $n = $SkuLookup[$_.skuId]; if ($n) { $n } else { $_.skuId } }) -join ', ') }}

# Build markdown table
$header = "### Licensed Users: $($results.Count)

| User | Display Name | Enabled | Licenses |
|---|---|---|---|"
$rows = $results | ForEach-Object {
    "| $($_.UserPrincipalName) | $($_.DisplayName) | $($_.AccountEnabled) | $($_.Licenses) |"
}
$md = @($header) + @($rows) -join "
"

# Return with explicit pass + markdown
@{
    CIPPStatus         = 'Passed'
    CIPPResults        = $results
    CIPPResultMarkdown = $md
}
```

</details>

<details>

<summary>Disabled Users with Active Licenses</summary>

Finds disabled accounts that still have a licence assigned, a common cost-waste indicator. Returns the matching rows as JSON, the default Result Display Type behaviour: no status wrapper needed, since a non-empty result already means a fail.

```powershell
# Find disabled users that still have licenses (wasted cost)
$Users = Get-CIPPTestData -Type 'Users'

# Return only disabled users with licenses: non-empty = fail
$Users | Where-Object {
    $_.accountEnabled -eq $false -and
    $_.assignedLicenses.Count -gt 0
} | Select-Object @{Name='UserPrincipalName'; Expression={ $_.userPrincipalName }},
    @{Name='DisplayName'; Expression={ $_.displayName }},
    @{Name='LicenseCount'; Expression={ @($_.assignedLicenses).Count }},
    @{Name='Message'; Expression={ 'Disabled account with active license(s)' }}
```

</details>

<details>

<summary>MFA Registration Gaps</summary>

Checks user registration details for accounts that have not registered any MFA method. Uses `Info` status so results are always informational rather than a hard fail.

```powershell
# Find users without any MFA method registered
$RegDetails = Get-CIPPTestData -Type 'UserRegistrationDetails'

$noMfa = $RegDetails | Where-Object {
    $_.methodsRegistered.Count -eq 0 -and
    $_.userType -ne 'guest'
} | Select-Object @{Name='UserPrincipalName'; Expression={ $_.userPrincipalName }},
    @{Name='UserDisplayName'; Expression={ $_.userDisplayName }},
    @{Name='IsAdmin'; Expression={ $_.isAdmin }},
    @{Name='Message'; Expression={ 'No MFA methods registered' }}

$count = @($noMfa).Count
if ($count -gt 0) {
    $header = "### Users Without MFA: $count

| User | Admin | Message |
|---|---|---|"
    $tableRows = $noMfa | ForEach-Object {
        "| $($_.UserPrincipalName) | $($_.IsAdmin) | $($_.Message) |"
    }
    $md = @($header) + @($tableRows) -join "
"
} else {
    $md = "### Users Without MFA: 0

All users have at least one MFA method registered."
}

@{
    CIPPStatus         = 'Info'
    CIPPResults        = $noMfa
    CIPPResultMarkdown = $md
}
```

</details>

<details>

<summary>Stale Guest Accounts</summary>

Identifies guest accounts with no sign-in inside a configurable window. Uses a `param` with a default so the threshold can be overridden from **Script Parameters (JSON)** without editing the script. Empty result means pass, non-empty means fail.

```powershell
# Find guest accounts with no recent sign-in
param($DaysThreshold = 90)

$Guests = Get-CIPPTestData -Type 'Guests'
$cutoff = (Get-Date).AddDays(-$DaysThreshold)

$Guests | Where-Object {
    -not $_.signInActivity.lastSignInDateTime -or
    [datetime]$_.signInActivity.lastSignInDateTime -lt $cutoff
} | Select-Object @{Name='UserPrincipalName'; Expression={ $_.userPrincipalName }},
    @{Name='DisplayName'; Expression={ $_.displayName }},
    @{Name='CreatedDateTime'; Expression={ $_.createdDateTime }},
    @{Name='LastSignIn'; Expression={ if ($_.signInActivity.lastSignInDateTime) { $_.signInActivity.lastSignInDateTime } else { 'Never' } }},
    @{Name='Message'; Expression={ "No sign-in within $DaysThreshold days" }}
```

</details>

<details>

<summary>Conditional Access Policy Summary</summary>

An informational summary of every Conditional Access policy grouped by state. Demonstrates `Group-Object`, a multi-section markdown report, and `%tenantname%` replacement. Always passes, since it is informational.

```powershell
# Summarize Conditional Access policies by state
$Policies = Get-CIPPTestData -Type 'ConditionalAccessPolicies'
$grouped = $Policies | Group-Object -Property state

$counts = $grouped | Select-Object @{Name='State'; Expression={ $_.Name }},
    @{Name='Count'; Expression={ $_.Count }}

# Build markdown summary (%tenantname% is replaced at runtime)
$header = "### %tenantname% CA Policies ($(@($Policies).Count) total)

| State | Count |
|---|---|"
$countRows = $counts | ForEach-Object {
    "| $($_.State) | $($_.Count) |"
}
$summaryTable = @($header) + @($countRows) -join "
"

# List each policy
$policyHeader = "| Policy | State | Created |
|---|---|---|"
$policyRows = $Policies | Sort-Object -Property state, displayName | ForEach-Object {
    "| $($_.displayName) | $($_.state) | $($_.createdDateTime) |"
}
$policyTable = @($policyHeader) + @($policyRows) -join "
"

$md = $summaryTable + "

---

" + $policyTable

@{
    CIPPStatus         = 'Passed'
    CIPPResults        = $counts
    CIPPResultMarkdown = $md
}
```

</details>

<details>

<summary>Conditional Access Licence Coverage (P1/P2)</summary>

Cross-references every enabled Conditional Access policy's included and excluded users and groups against each user's assigned Microsoft Entra ID licence, and lists anyone in scope for a policy without the licence that policy needs: Microsoft Entra ID P1 as a baseline, or P2 where the policy also evaluates sign-in or user risk. Group membership checked is direct membership only; nested and dynamic-membership groups are not expanded, and role-scoped policy assignments are not evaluated.

```powershell
# Cross-reference Conditional Access policy scope (users + groups) against Entra ID P1/P2 licensing
$Policies = Get-CIPPTestData -Type 'ConditionalAccessPolicies'
$Groups   = Get-CIPPTestData -Type 'Groups'
$Users    = Get-CIPPTestData -Type 'Users'

# Microsoft Entra ID P1 / P2 service plan IDs: stable across every SKU that bundles them
$P1PlanId = '41781fb2-bc02-4b7c-bd55-b576c07bb09d'
$P2PlanId = 'eec0eb4f-6444-4f95-aba0-50c24d67f998'

# id -> UPN, UPN -> enabled state, UPN -> highest licensed Entra ID tier
$UpnById     = @{}
$UserEnabled = @{}
$UserTier    = @{}
foreach ($User in $Users) {
    $UpnById[$User.id] = $User.userPrincipalName
    $UserEnabled[$User.userPrincipalName] = [bool]$User.accountEnabled
    $EnabledPlans = @($User.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' } | Select-Object -ExpandProperty servicePlanId)
    $UserTier[$User.userPrincipalName] = if ($EnabledPlans -contains $P2PlanId) { 'P2' }
        elseif ($EnabledPlans -contains $P1PlanId) { 'P1' }
        else { 'None' }
}

# Group id -> direct member UPNs
$GroupMembers = @{}
foreach ($Group in $Groups) {
    $GroupMembers[$Group.id] = @($Group.members | Where-Object { $_.userPrincipalName } | Select-Object -ExpandProperty userPrincipalName)
}

$Gaps = foreach ($Policy in ($Policies | Where-Object { $_.state -in @('enabled', 'enabledForReportingButNotEnforced') })) {
    # A policy that evaluates sign-in or user risk needs P2; every other enabled policy needs P1
    $RequiredTier = if (@($Policy.conditions.signInRiskLevels).Count -gt 0 -or @($Policy.conditions.userRiskLevels).Count -gt 0) { 'P2' } else { 'P1' }

    $IncludeUsers  = @($Policy.conditions.users.includeUsers)
    $IncludeGroups = @($Policy.conditions.users.includeGroups)
    $ExcludeUsers  = @($Policy.conditions.users.excludeUsers)
    $ExcludeGroups = @($Policy.conditions.users.excludeGroups)

    $ScopedUpns = if ($IncludeUsers -contains 'All') {
        @($Users | Select-Object -ExpandProperty userPrincipalName)
    } else {
        $FromUsers  = @($IncludeUsers  | ForEach-Object { $UpnById[$_] })
        $FromGroups = @($IncludeGroups | ForEach-Object { $GroupMembers[$_] })
        @($FromUsers + $FromGroups | Where-Object { $_ } | Sort-Object -Unique)
    }

    $ExcludedUpns  = @($ExcludeUsers  | ForEach-Object { $UpnById[$_] })
    $ExcludedUpns += @($ExcludeGroups | ForEach-Object { $GroupMembers[$_] })

    $ScopedUpns | Where-Object {
        $_ -and $_ -notin $ExcludedUpns -and $UserEnabled[$_] -and
        -not (($RequiredTier -eq 'P1' -and $UserTier[$_] -in @('P1', 'P2')) -or ($RequiredTier -eq 'P2' -and $UserTier[$_] -eq 'P2'))
    } | Select-Object @{Name='Policy'; Expression={ $Policy.displayName }},
        @{Name='RequiredTier'; Expression={ $RequiredTier }},
        @{Name='User'; Expression={ $_ }},
        @{Name='CurrentTier'; Expression={ $UserTier[$_] }}
}
$Gaps = @($Gaps | Sort-Object -Property Policy, User)

# Build markdown (%tenantname% is replaced at runtime)
$header = "### %tenantname%: Conditional Access Licence Gaps

Policies evaluated: $(@($Policies).Count) | Users with a licensing gap: $(@($Gaps | Select-Object -ExpandProperty User -Unique).Count)

| Policy | Required | User | Current |
|---|---|---|---|"
$rows = $Gaps | ForEach-Object {
    "| $($_.Policy) | $($_.RequiredTier) | $($_.User) | $($_.CurrentTier) |"
}

$md = if (@($Gaps).Count -gt 0) {
    @($header) + @($rows) -join "
"
} else {
    "### %tenantname%: Conditional Access Licence Gaps

All enabled users in scope for Conditional Access hold the required Entra ID licence tier."
}

@{
    CIPPStatus         = if (@($Gaps).Count -gt 0) { 'Failed' } else { 'Passed' }
    CIPPResults        = $Gaps
    CIPPResultMarkdown = $md
}
```

</details>

## Configuration Options

| Option                | Description                                                                                                                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Script Name           | The display name for the test.                                                                                                                                                                                                        |
| Category              | Existing options: `License Management`, `Security`, `Compliance`, `User Management`, `Group Management`, `Device Management`, `Guest Management`, `General`. Create your own by typing it and selecting **Add option: \<your text>**. |
| Description           | Describes what the script checks or monitors.                                                                                                                                                                                         |
| Risk Level            | `Low`, `Medium`, `High` or `Critical`. Used for alert severity.                                                                                                                                                                       |
| Pillar                | `Identity`, `Devices` or `Data`. Classifies which area the test belongs to.                                                                                                                                                           |
| User Impact           | `Low`, `Medium` or `High`.                                                                                                                                                                                                            |
| Implementation Effort | `Low`, `Medium` or `High`.                                                                                                                                                                                                            |
| Result Display Type   | `JSON` or `Markdown`. Controls the default rendering of the test output. A script returning `CIPPResultMarkdown` overrides this.                                                                                                      |
| Result Mode           | `Auto`, `Always Pass`, `Always Info` or `Always Investigate`. Under `Auto` the script output determines the outcome; the others force that status regardless of what the script returns.                                              |
| Enable Script         | Whether the test runs during scheduled test execution.                                                                                                                                                                                |
| Notify on Alert       | Raises an alert through your configured notification channels when the test produces a matching status.                                                                                                                               |
| Alert on Status       | Which statuses trigger an alert: `Failed`, `Passed`, `Info`, `Investigate` or `All`. Only shown once **Notify on Alert** is enabled.                                                                                                  |

{% hint style="info" %}
Alerts are deduplicated per tenant per day, so a test failing on every scheduled run raises one alert a day for that tenant rather than one per run.
{% endhint %}

## Markdown / PowerShell

**Markdown Result Template** appears only when **Result Display Type** is set to `Markdown`, and defines how the result is rendered. Where a previous test run has produced output, CIPP detects the result schema from it and offers the available fields for typed markdown, so run the test once before writing the template.

**PowerShell Script** is the script itself, written in a full editor with syntax highlighting. Type `%` to insert replacement variables.

## Test Script Output

Runs the test against the tenant currently chosen in tenant-select.md and renders the output using the Return Type and Markdown Template currently in the form.

**Script Parameters (JSON)** optionally passes parameters to the run, as a JSON object such as `{"DaysThreshold": 30}`.

**Run Test** executes the script. It is unavailable until the test has been saved, and again whenever there are unsaved changes, because a test run uses the saved version of the script rather than what is on screen. A save button sits next to it for exactly this reason.

{% hint style="info" %}
Runs from this page are preview only. Results are stored only when a scheduled tenant test run executes the test with **Enable Script** turned on.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
