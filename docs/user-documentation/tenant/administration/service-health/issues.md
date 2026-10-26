# Issues

This tab lists the service health issues Microsoft has posted for the selected tenant: the incidents and advisories about outages and degraded service, with their status, the affected service and feature, and when they started and were last updated. The other Service Health tabs are described on [README.md](README.md "mention").

With All Tenants selected, an issue Microsoft posted to several tenants is listed once, and the **Tenant** column shows how many tenants it reached.

## Summary Bar

Selecting a tile filters the table to the issues it counts.

| Tile              | Description                                                         |
| ----------------- | ------------------------------------------------------------------- |
| Open              | How many issues are unresolved.                                     |
| Open incidents    | How many unresolved issues Microsoft has classified as incidents.   |
| Open advisories   | How many unresolved issues Microsoft has classified as advisories.  |
| Services affected | How many distinct services have at least one unresolved issue.      |

## Filters

| Filter          | Shows                                                         |
| --------------- | ------------------------------------------------------------- |
| Open            | Issues Microsoft has not yet marked as resolved.              |
| Open incidents  | Unresolved issues Microsoft has classified as incidents.      |
| Open advisories | Unresolved issues Microsoft has classified as advisories.     |
| Resolved        | Issues Microsoft has marked as resolved.                      |

## Table Details

The properties returned are for the Graph resource type `serviceHealthIssue`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/servicehealthissue?view=graph-rest-1.0).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

Below the issue details, the flyout lists every update Microsoft has posted for the issue, newest first, with the newest expanded. With All Tenants selected, it also lists every tenant the issue was posted to. Links inside an update open in a new browser tab.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
