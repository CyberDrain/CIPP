# Directory Audits

Directory audits are Entra ID's own record of administrative activity in the tenant: role assignments, application consent, user and group changes, policy edits and so on. This page reads that log live from Microsoft rather than from anything CIPP has stored, so it reflects the tenant's current retention period rather than CIPP's history. Entries are listed newest first, and the table honors the tenant selector at the top of CIPP.

{% hint style="info" %}
This is a live Graph query, so no data appears until a tenant is selected, and the retention available depends on the tenant's Entra ID licensing rather than on CIPP.
{% endhint %}

## Table Details

The properties returned are for the Graph resource type `directoryAudit`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/directoryaudit?view=graph-rest-1.0#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
