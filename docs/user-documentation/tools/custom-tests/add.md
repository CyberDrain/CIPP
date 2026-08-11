# Add/Edit Custom Test

This page creates a new custom test and is also where existing tests are edited. Opening it from **Add Test** gives you a blank form; opening it through **Edit Test** on an existing test loads that test's current version, and saving creates a new version rather than overwriting the old one.

{% hint style="danger" %}
Custom tests are read-only. A test cannot write to CIPP's tables or make any change in the client tenant.
{% endhint %}

The page is arranged as four collapsible sections. **Test Guidance** and **Test Script Output** open by default when adding a test and editing one respectively.

## Test Guidance

Reference material for writing the script, worth reading before your first test. It covers how a result status is decided, the constraints the script runs under, and the data available to it, and includes four worked example scripts you can copy as a starting point.

### How the Result Is Decided

| Outcome         | How to produce it                                                                                                                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pass            | Return `$null`, `$false`, an empty string, or `@()`.                                                                                                                                                                                  |
| Fail            | Return any non-empty value. Whatever is returned becomes the test output.                                                                                                                                                             |
| Explicit status | Return a hashtable containing `CIPPStatus` (`Passed`, `Failed`, `Info` or `Investigate`), `CIPPResults`, and optionally `CIPPResultMarkdown` to control both the status and how it renders. Only honored when Result Mode is `Auto`. |

### Scripting Constraints

{% hint style="warning" %}
Scripts run in PowerShell **ConstrainedLanguage** mode, so only approved cmdlets are available. `New-Object`, `[pscustomobject]@{}` casts, and .NET and reflection calls are all blocked. Build rows with `Select-Object @{Name;Expression}` and return a plain `@{}` hashtable instead.
{% endhint %}

Data is read through `Get-CIPPTestData` with a `-Type` parameter. The tenant is locked automatically, so do not pass `-TenantFilter`. **View Cached Types** opens a dialog listing every available type with its description, and the eye icon beside each one shows sample data from the currently selected tenant, which is the quickest way to see the shape of what you will be working with.

Type `%` anywhere in the script to insert a replacement variable, such as `%tenantid%` or `%defaultdomain%`, alongside any custom variables you have defined.

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
