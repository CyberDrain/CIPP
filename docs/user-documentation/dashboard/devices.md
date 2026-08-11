# Devices

This tab shows how the tenant performed against the device checks in the selected test suite, and gives you the detail and remediation guidance for each one.

The suite is chosen from the controls at the top of the tab, which behave exactly as they do on the Overview tab. Changing the suite here changes it across the whole dashboard. A description of the selected suite is shown above the table.

{% hint style="info" %}
Device checks are assessed against the tenant's Intune configuration, so a suite's device results depend on the tenant having devices enrolled and managed. Suites that cover only identity controls will show no results here.
{% endhint %}

## Table Details

| Column | Description                                                                                        |
| ------ | -------------------------------------------------------------------------------------------------- |
| Name   | The name of the check that was run.                                                                |
| Risk   | How much risk this setting presents to the client if misconfigured, shown as High, Medium, or Low. |
| Status | The outcome of the check: Passed, Failed, Investigate, or Skipped.                                 |

Additional columns can be shown from the **Columns** menu. See [table-features.md](../shared-features/table-features.md "mention").

## Filters

Preset filters are available from the **Filters** button for each status and each risk level.

| Filter      | Description                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------ |
| Passed      | Checks the tenant satisfied.                                                                           |
| Failed      | Checks the tenant did not satisfy.                                                                     |
| Investigate | Checks that could not be resolved to a pass or fail and need a human decision.                         |
| Skipped     | Checks that did not run, usually because the tenant lacks the license or feature the check applies to. |
| High Risk   | Checks carrying a high risk rating, whatever their status.                                             |
| Medium Risk | Checks carrying a medium risk rating.                                                                  |
| Low Risk    | Checks carrying a low risk rating.                                                                     |

A status filter and a risk filter cannot both be active at once, since both act on the table's columns. To combine them, apply one preset and then filter the other column manually.

## Test Detail

Clicking anywhere on a row opens the Extended Info flyout with the full detail for that check. The up and down arrows at the top of the flyout move through the tests without closing it, and the cross closes it.

### Summary

Four indicators run across the top of the flyout.

| Indicator          | Description                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------- |
| Risk               | How much risk this setting presents to the client if misconfigured.                           |
| User Impact        | How much the recommended remediation will affect end users once applied.                      |
| Effort             | How much work the remediation is expected to take.                                            |
| Standard Available | Whether a CIPP standard exists that satisfies this check, with a count of matching standards. |

### CIPP Standards That Satisfy This Test

Where CIPP standards exist that would remediate or enforce the check, they are listed here by name. This section is only shown when there is at least one match, and is the fastest route from a failed check to the standard that fixes it.

### Test Outcome

The check's name and its status, followed by the detail of what was found in the tenant. For most checks this is a formatted explanation of the result, often including tables of the specific devices or policies that passed or failed.

### What Did We Check

The category the check belongs to, followed by a description of what the check looks for and why it matters. Where the check maps to vendor guidance, links to that documentation appear here.

## All Tenants View

With the tenant selector on **All Tenants**, this tab shows device results across every tenant instead. Four tiles summarize the estate.

| Tile                    | Description                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| Tenants failing a check | How many tenants have at least one failing device check, out of those with results.                |
| Failed checks           | The total number of failed checks, with the total result count across the estate.                  |
| High-risk failures      | Failed checks carrying a high risk rating.                                                         |
| Pass rate               | Passed checks as a percentage of passed plus failed. Investigate and skipped results are excluded. |

Below the tiles, a table lists the individual results.

| Column      | Description                          |
| ----------- | ------------------------------------ |
| Tenant Name | The tenant the result belongs to.    |
| Name        | The name of the check that was run.  |
| Suite       | The test suite the check comes from. |
| Status      | The outcome of the check.            |
| Risk        | The risk rating of the check.        |
| Category    | The category the check belongs to.   |
| Last Run    | When the check last ran.             |

{% hint style="info" %}
By default this table shows only Failed and Investigate results, and the heading reflects that. Use **Show all results** to include passed and skipped checks as well, which also adds Passed and Skipped to the available filters. The tiles are calculated across every status either way, so the figures do not change when you toggle the view.
{% endhint %}

Clicking a row opens the same detail flyout as the per-tenant view. The full detail for that one result is fetched when you open it, so there may be a brief pause before it appears.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View tenant dashboard</td><td>Opens this tab for the tenant the selected result belongs to.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../.gitbook/includes/feature-request.md" %}
