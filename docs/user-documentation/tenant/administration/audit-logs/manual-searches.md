# Manual Searches

Alongside the search windows CIPP runs automatically, you can queue an audit log search of your own against a specific tenant, time range and set of filters. This is the tool for investigations: chasing a suspected compromise, answering a client's question about who deleted a file, or checking activity for a period before your alert rules existed. This page lists the searches you have queued, and lets you review the records they returned or push them through your alert rules.

{% hint style="info" %}
Only searches queued in the last 7 days are listed. Older searches age out of CIPP's tracking even if the query still exists in the tenant.
{% endhint %}

## Action Buttons

**New Search** opens the Create New Audit Log Search flyout. Complete the fields, then select **Create Search** to queue it, or **Cancel** to discard.

| Field                   | Description                                                                                                                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Search Name             | A name for the search, used to identify it in the table afterwards. Required.                                                                                                                   |
| Tenant                  | The tenant to search. Defaults to the tenant currently selected in CIPP. Required.                                                                                                              |
| Start Date & Time       | The beginning of the period to search. Required.                                                                                                                                                |
| End Date & Time         | The end of the period to search. Required.                                                                                                                                                      |
| Record Types            | Restricts the search to particular categories of audit record, such as Exchange Admin, SharePoint File Operation or Microsoft Teams. Leave empty to search all types.                           |
| Keywords                | Free text to search for across the non-indexed parts of the audit records. Enter each term separately.                                                                                          |
| Operations              | The specific activities to look for, such as Hard Delete, New Inbox Rule or Anonymous Link Created. Choose from the list or type your own if the operation you need is not offered.             |
| User Principal Names    | Restricts the search to activity performed by particular users.                                                                                                                                 |
| IP Addresses            | Restricts the search to activity originating from particular addresses.                                                                                                                         |
| Object IDs              | Restricts the search to particular objects. For SharePoint and OneDrive this is the full path of the file or folder; for Exchange admin activity it is the name of the object that was changed. |
| Administrative Units    | Restricts the search to records tagged with the chosen administrative units in the tenant.                                                                                                      |
| Process Logs for Alerts | Stores the search so its results can be run through your alert rules. Leave off for a purely investigative search.                                                                              |

{% hint style="info" %}
Every filter you add narrows the search further, so start broad and tighten from there. A search with no filters beyond the date range returns everything in the window, which is slow but occasionally what you want.
{% endhint %}

Searches are not instant. Microsoft queues the query and works through it in the background, so a newly created search sits at `notStarted` or `running` for a while before its records become available.

## Table Details

The properties returned are for the Graph resource type `microsoft.graph.security.auditLogQuery`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/security-auditlogquery?view=graph-rest-1.0#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Results</td><td>Opens the <a data-mention href="search-results.md">search-results.md</a> for the selected search. Only useful once the search has reached a status of succeeded.</td><td>false</td></tr><tr><td>Process Logs</td><td>Runs the search results through your alert rules after confirmation, generating alerts for anything that matches. Nothing happens for records that match no rule.</td><td>true</td></tr><tr><td>Copy Search</td><td>Opens the flyout as <strong>Copy Audit Log Search</strong>, filled in with the selected search's date range and filters and its name with <code> - Copy</code> added, so a similar search can be queued without re-entering everything. The tenant is set to the one currently selected, and <strong>Process Logs for Alerts</strong> starts off. Adjust anything needed, then select <strong>Create Search</strong>.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
