# Packages

This page lists the Microsoft Agent 365 agent packages registered in the selected tenant.

The list is read live from the tenant's package catalog. Because the default catalog listing omits agents, CIPP combines it with a second query for agent packages and merges the results into a single deduplicated view, so both agents and Microsoft 365 apps appear together.

{% hint style="info" %}
The Package Management API this page relies on requires a Microsoft Agent 365 license on the tenant. Without one, the list will not populate.
{% endhint %}

## Table Details

| Column                  | Description                                                                              |
| ----------------------- | ---------------------------------------------------------------------------------------- |
| Display Name            | The package's display name.                                                              |
| Type                    | The package/agent type.                                                                  |
| Publisher               | The publisher of the package.                                                            |
| Version                 | The package version.                                                                     |
| Supported Hosts         | The Microsoft 365 surfaces the package can run on, for example Teams, Copilot, Outlook.  |
| Element Types           | The component types bundled in the package (bots, declarative agents, extensions, etc.). |
| Available To            | Who the package is made available to (allowed scope).                                    |
| Deployed To             | Who the package is actually deployed/assigned to.                                        |
| Is Blocked              | Whether the package is blocked in the tenant.                                            |
| Last Modified Date Time | When the package was last modified.                                                      |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

The flyout also fetches the package's full detail record live from the tenant, adding the allowed and acquired users and groups and the package's element details, which the list view does not include.

{% include "../../../../.gitbook/includes/feature-request.md" %}
