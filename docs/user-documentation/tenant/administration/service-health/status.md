# Status

This tab lists the current health of each Microsoft 365 service for the selected tenant, as Microsoft reports it, so you can tell at a glance whether a problem a user is reporting is a known service issue. The other Service Health tabs are described on [README.md](README.md "mention").

With All Tenants selected, services that share the same status are combined into a single row, and the **Tenant** column shows how many tenants report it.

## Summary Bar

| Tile                 | Description                                                                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Services             | How many distinct services are listed.                                                                             |
| Services with issues | How many services are reporting any status other than operational.                                                 |
| Degraded             | How many services are reporting degraded service. Selecting the tile filters the table to those services.         |
| Interrupted          | How many services are reporting a service interruption. Selecting the tile filters the table to those services.  |

## Filters

| Filter          | Shows                                                       |
| --------------- | ----------------------------------------------------------- |
| Not operational | Services reporting any status other than operational.       |
| Degraded        | Services Microsoft reports as running in a degraded state.  |
| Interrupted     | Services Microsoft reports as interrupted.                  |

## Table Details

The properties returned are for the Graph resource type `serviceHealth`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/servicehealth?view=graph-rest-1.0).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

With All Tenants selected, the flyout lists every tenant reporting that service and status.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
