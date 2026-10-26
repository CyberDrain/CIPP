# Message Center

This tab lists the Microsoft 365 message center posts for the selected tenant: Microsoft's notices of new, changing, and retiring features, planned changes, and posts that need an administrator to act by a given date. The other Service Health tabs are described on [README.md](README.md "mention").

With All Tenants selected, a post Microsoft sent to several tenants is listed once, and the **Tenant** column shows how many tenants it reached.

## Summary Bar

| Tile             | Description                                                                                                      |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| Action required  | How many posts carry a date by which action is required.                                                         |
| Major changes    | How many posts Microsoft has flagged as a major change. Selecting the tile filters the table to those posts.     |
| High or critical | How many posts carry a severity above normal.                                                                    |
| Plan for change  | How many posts are in the Plan for change category. Selecting the tile filters the table to those posts.         |

## Filters

| Filter               | Shows                                                                   |
| -------------------- | ----------------------------------------------------------------------- |
| Major changes        | Posts Microsoft has flagged as a major change.                          |
| High or critical     | Posts with a severity above normal.                                     |
| Plan for change      | Posts announcing changes you may need to prepare for.                   |
| Prevent or fix issue | Posts about known problems and the steps to prevent or fix them.        |

## Table Details

The properties returned are for the Graph resource type `serviceUpdateMessage`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/serviceupdatemessage?view=graph-rest-1.0).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

Below the post details, the flyout shows the full text of the post. With All Tenants selected, it also lists every tenant the post was sent to. Links inside the post open in a new browser tab.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
