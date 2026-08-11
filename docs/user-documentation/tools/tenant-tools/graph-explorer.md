# Graph Explorer

The Graph Explorer builds ad hoc reports directly from the Microsoft Graph API. Rather than returning a raw JSON representation of the Graph object, it renders the response as a table with the usual sorting, filtering and export options. Run one of the built-in queries, load a preset you or a colleague has saved, or craft your own request to customize the data to your liking. Results are always scoped to the tenant chosen in the tenant-select.md.

{% hint style="warning" %}
Graph Explorer is a moderately advanced tool. Understanding the Microsoft Graph API and the various ways to influence its output can be difficult. If you get stuck crafting a query, please don't hesitate to ask questions in the CyberDrain Discord server, or contact support if you are a sponsoring user or organization.
{% endhint %}

## Microsoft Graph

Microsoft Graph is the source of the data for much of CIPP and is the vehicle for the data you'll see in the Graph Explorer. Familiarity with how API GET calls are made to Microsoft Graph is helpful when creating custom queries. Since CIPP can call both the v1.0 and beta endpoints, both references are below:

{% embed url="https://learn.microsoft.com/en-us/graph/api/overview?view=graph-rest-1.0" %}

{% embed url="https://learn.microsoft.com/en-us/graph/api/overview?view=graph-rest-beta" %}

## Action Buttons

The **Select a query** dropdown lists every query available to you, grouped into **Built-In** (shipped with CIPP) and **Custom** (presets you have saved, plus presets other users in your instance have shared). Choosing a query loads its parameters but does not run it.

**Run** executes the currently loaded query against the selected tenant. The button stays disabled until you have either chosen a query from the dropdown or applied one from the **Edit Query** flyout. Selecting a different query from the dropdown discards any unapplied edits, so **Run** always uses the preset as saved.

**View JSON** replaces the results table with a read-only JSON editor showing the raw Graph response, useful for inspecting nested properties that the table flattens. The button becomes **View Table** to switch back. The query bar stays available in both views.

<details>

<summary>Edit Query</summary>

Opens the **Graph Explorer Query** flyout, where you can build a request from scratch or adjust the one currently loaded. **Select a preset** at the top populates the settings from an existing query as a starting point, and **Preset Name** sets the name used when you save it.

| Field                          | Description                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Endpoint                       | The Graph endpoint to query, entered without the host or version prefix (for example `users`). This is the only required field.                                                                                                                                                                                                             |
| API Version                    | The Graph API version to call, either `beta` (the default) or `v1.0`.                                                                                                                                                                                                                                                                       |
| Select                         | The object properties to include in the response. CIPP reads the available properties from the endpoint as you type it, so the list populates once a valid endpoint is entered. The chosen properties also become the columns of the results table, in the order selected. Leaving this empty returns every property the endpoint provides. |
| Filter                         | An OData `$filter` expression used to restrict which objects are returned.                                                                                                                                                                                                                                                                  |
| Expand                         | An OData `$expand` expression used to include related entities in the response.                                                                                                                                                                                                                                                             |
| Top                            | The maximum number of records to request per page.                                                                                                                                                                                                                                                                                          |
| Search                         | An OData `$search` query. Not every endpoint supports searching.                                                                                                                                                                                                                                                                            |
| Order By                       | The sort order to request from Graph, for example `displayName asc`.                                                                                                                                                                                                                                                                        |
| Format                         | The `$format` parameter for report data, for example `application/json`.                                                                                                                                                                                                                                                                    |
| Reverse Tenant Lookup          | Resolves tenant identifiers found in the results back to tenant names and adds the details as a `TenantInfo` property. Useful for reports that reference tenants by ID, such as guest or cross-tenant data.                                                                                                                                 |
| Reverse Tenant Lookup Property | The property holding the tenant identifier to resolve, defaulting to `tenantId`. Only shown when **Reverse Tenant Lookup** is enabled.                                                                                                                                                                                                      |
| Disable Pagination             | Returns only the first page of results instead of following `@odata.nextLink` until the full set is retrieved. Useful for sampling a large endpoint quickly.                                                                                                                                                                                |
| Use $count                     | Adds the `$count` parameter to the request. Some `$filter` and `$search` expressions require it.                                                                                                                                                                                                                                            |
| As App                         | Runs the request using the application identity instead of the delegated one. Some endpoints only return data, or only return complete data, when called as the application.                                                                                                                                                                |
| Share Preset                   | Makes the preset visible to every other user in your CIPP instance when saved. Leave it off to keep the preset to yourself.                                                                                                                                                                                                                 |

The buttons at the bottom of the flyout act on the query you have built:

| Button          | Description                                                                                                                                                                                        |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Apply Filter    | Runs the query and closes the flyout. The results appear in the current view.                                                                                                                      |
| Schedule Report | Opens the **Schedule Graph Explorer Report** flyout to run the query on a schedule and deliver the output.                                                                                         |
| Save Preset     | Saves the query as a custom preset under the entered **Preset Name**. On a preset you do not own the button reads **Copy Preset** and saves your own copy instead, leaving the original untouched. |
| Delete Preset   | Deletes the selected custom preset. Disabled unless you are the owner of the preset.                                                                                                               |
| Import/Export   | Opens the **Import / Export Graph Explorer Preset** flyout containing the current query as JSON.                                                                                                   |

</details>

## Presets

Presets let you keep a query for reuse and hand it to other people. Built-in presets are read-only: loading one and saving it creates a custom preset of your own rather than overwriting the original. The same applies to a shared preset belonging to another user, where the save button changes to **Copy Preset**.

A preset is visible to you if you own it or if its owner enabled **Share Preset**. Only the owner can save over or delete a preset, so the **Delete Preset** button is disabled on anything you did not create.

To move a preset between CIPP instances, use **Import/Export**. With a preset loaded, the flyout shows its JSON ready to copy. To bring one in, paste the JSON someone has shared with you and click **Import Template**, and it is added to your custom presets.

## Scheduling Reports

**Schedule Report** hands the current query to the scheduler as a `Get-GraphRequestList` task, with the endpoint, query parameters and switches already filled in from the flyout. The task is named after the loaded preset where there is one.

Set the recurrence and choose how you want the output delivered (PSA, email or webhook), then save the task. The remaining fields behave exactly as they do elsewhere in the scheduler:

{% content-ref url="../scheduler/task.md" %}
[task.md](../scheduler/task.md)
{% endcontent-ref %}

## Reviewing Results

Results render as a table with all the standard [table-features.md](../../shared-features/table-features.md "mention"), including export to PDF or CSV. Where the query specified **Select**, those properties become the table columns; otherwise every property returned by the endpoint is shown.

{% hint style="info" %}
A warning is displayed in place of the results if no tenant is selected. Choose a tenant and run the query again.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
