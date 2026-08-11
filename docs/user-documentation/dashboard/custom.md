# Custom

This tab shows the results of the custom tests in the selected test suite, and gives you the detail for each one.

Custom tests are ones you have written yourself rather than checks CIPP ships. They only appear here if the selected suite includes them, so a built-in suite will normally show nothing on this tab. To write custom tests or add them to a suite, see [custom-tests](../tools/custom-tests/ "mention").

The suite is chosen from the controls at the top of the tab, which behave exactly as they do on the Overview tab. Changing the suite here changes it across the whole dashboard. A description of the selected suite is shown above the table.

## Table Details

| Column   | Description                                                                                        |
| -------- | -------------------------------------------------------------------------------------------------- |
| Name     | The name of the check that was run.                                                                |
| Category | The category assigned to the check when it was written.                                            |
| Risk     | How much risk this setting presents to the client if misconfigured, shown as High, Medium, or Low. |
| Status   | The outcome of the check: Passed, Failed, Investigate, or Skipped.                                 |

Additional columns can be shown from the **Columns** menu. See [table-features.md](../shared-features/table-features.md "mention").

## Filters

Preset filters are available from the **Filters** button for each status and each risk level.

| Filter      | Description                                                                    |
| ----------- | ------------------------------------------------------------------------------ |
| Passed      | Checks the tenant satisfied.                                                   |
| Failed      | Checks the tenant did not satisfy.                                             |
| Investigate | Checks that could not be resolved to a pass or fail and need a human decision. |
| Skipped     | Checks that did not run.                                                       |
| High Risk   | Checks carrying a high risk rating, whatever their status.                     |
| Medium Risk | Checks carrying a medium risk rating.                                          |
| Low Risk    | Checks carrying a low risk rating.                                             |

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

### Test Outcome

The check's name and its status, followed by whatever the test returned. How this is presented depends on how the test was written.

| Test output                       | How it is shown                                                                              |
| --------------------------------- | -------------------------------------------------------------------------------------------- |
| A markdown result                 | Rendered as formatted text, including any tables, lists, and links the test produced.        |
| Raw data with a markdown template | The template is filled in with values from the returned data and rendered as formatted text. |
| Raw data returning JSON           | Shown as a formatted, syntax-highlighted JSON code block.                                    |

{% hint style="info" %}
If a custom test returns nothing usable, this section does not appear at all. Where a test is producing no output, check the script's return value and its markdown template.
{% endhint %}

### What Did We Check

The category assigned to the check, followed by the description recorded against it. Because both come from the test definition rather than from CIPP, how useful this section is depends on how the test was written. A description written in markdown is rendered as formatted text, and any links it contains open in a new tab.

## All Tenants View

With the tenant selector on **All Tenants**, this tab shows custom test results across every tenant instead. Four tiles summarize the estate.

| Tile                    | Description                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| Tenants failing a check | How many tenants have at least one failing custom check, out of those with results.                |
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
