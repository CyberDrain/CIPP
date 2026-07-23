# Custom Test Report

This page will display custom tests that run against the selected tenant. Select a custom test from the dropdown or leave empty. Clicking the "Run Custom Tests" will trigger a fresh run of the tests.

## Table Details

| Column   | Description                                                                                                                                                    |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant   | The tenant the result applies to. With a single tenant selected the report shows just that tenant; with AllTenants selected it lists results for every tenant. |
| Name     | The name of the custom test that produced this result.                                                                                                         |
| Enabled  | Whether the custom test is currently turned on. Only enabled tests are included when you use "Run Custom Tests."                                               |
| Risk     | The risk level of the finding — `High`, `Medium`, or `Low` — to help you prioritise. Also available as the High/Medium/Low Risk quick filters.                 |
| Status   | The outcome of the test: `Passed`, `Failed`, `Investigate`, or `Skipped`. Also available as the matching quick filters.                                        |
| Last Run | When this test was last evaluated against the tenant.                                                                                                          |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

***

{% include "../../../../.gitbook/includes/feature-request.md" %}
