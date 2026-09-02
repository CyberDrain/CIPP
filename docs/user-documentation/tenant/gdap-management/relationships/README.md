# Relationships

This page lists every delegated admin relationship attached to your Microsoft partner tenant. It shows the status of each relationship, the customer it belongs to, when it was created and activated, when it expires, and the roles it grants. Preset filters are available for the **Active**, **Approval Pending**, **Terminating**, and **Terminated** statuses.

## Filters

| Filter           | Shows                                                                     |
| ---------------- | ------------------------------------------------------------------------- |
| Active           | Relationships that are currently active.                                  |
| Approval Pending | Relationships awaiting the customer's approval before they become active. |
| Terminating      | Relationships that are in the process of being terminated.                |
| Terminated       | Relationships that have already been terminated.                          |

## Table Details

The properties returned are for the Graph resource type `delegatedAdminRelationship`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/delegatedadminrelationship?view=graph-rest-beta).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Relationship</td><td>Opens the <a data-mention href="relationship/">relationship</a> for the selected relationship, showing its full details and role mappings.</td><td>false</td></tr><tr><td>Start Onboarding</td><td>Opens the <a data-mention href="../../../../setup/installation/gdap-invite-wizard.md">gdap-invite-wizard.md</a> page with the selected relationship already chosen.</td><td>false</td></tr><tr><td>Open Relationship in Partner Center</td><td>Opens the relationship in Microsoft Partner Center in a new tab.</td><td>false</td></tr><tr><td>Enable automatic extension</td><td>Enables automatic extension on the relationship, so it renews rather than expiring. Relationships that include the Global Administrator role are not eligible.</td><td>true</td></tr><tr><td>Remove Global Administrator from Relationship</td><td>Removes the Global Administrator role from the relationship. This is the only role change that can be made to an existing relationship.</td><td>true</td></tr><tr><td>Reset Role Mapping</td><td>Applies a role template of your choosing to the relationship. Group assignments that are not part of the template are removed, existing assignments are updated to match, and any missing assignments are created. Use this to repair relationships with overlapping roles or incorrect group assignments.</td><td>true</td></tr><tr><td>Terminate Relationship</td><td>Ends the relationship and removes all delegated access it granted to the customer tenant.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
