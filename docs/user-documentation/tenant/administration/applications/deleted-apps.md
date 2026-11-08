# Deleted Apps

Entra keeps deleted app registrations and enterprise applications (service principals) for 30 days before removing them for good. This page lists the ones deleted from the selected tenant in that window, so an application deleted by mistake from [enterprise-apps](enterprise-apps/ "mention") or [app-registrations](app-registrations/ "mention") can be brought back. It needs a single tenant selected.

Deleting an app registration also deletes its enterprise application in the same tenant, but the two are restored separately. **Related Deleted** shows when the matching app registration or enterprise application is in the list too.

Other deleted directory objects, such as users and groups, are on [deleted-items.md](../../../identity/administration/deleted-items.md "mention").

## Table Details

| Column          | Description                                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| Display Name    | The name of the deleted application.                                                                               |
| Type            | App registration or Enterprise app.                                                                                |
| App ID          | The application (client) ID, shared by an app registration and its enterprise applications.                       |
| Publisher       | The publisher domain of an app registration, or the publisher name of an enterprise application.                  |
| Deleted Date    | When the application was deleted.                                                                                  |
| Days Left       | Days left before Entra removes the application for good and it can no longer be restored.                         |
| Related Deleted | Whether the matching app registration or enterprise application with the same App ID is deleted too.               |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Restore</td><td>Restores the application. The result says when the matching app registration or enterprise application is still deleted and needs restoring too.</td><td>false</td></tr><tr><td>Permanently Delete</td><td>Removes the application from the deleted items for good, after a confirmation prompt. It can no longer be restored.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

Restoring and permanently deleting need the Tenant.Application.ReadWrite permission. Viewing the list needs Tenant.Application.Read.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
