# Permission Sets

Permission sets are named collections of API permissions stored in CIPP rather than in any tenant. They are the reusable building block behind application deployment: an application template references a permission set and deploying that template grants the permissions in the set to the application in the target tenant. Defining the permissions once here keeps every deployment of an application consistent.

Sets are created by hand from this page, and also automatically by the **Create Template from App** action on [enterprise-apps](enterprise-apps/ "mention") and [app-registrations](app-registrations/ "mention"), which saves the source application's permissions as a set named after the application, suffixed with "(Auto-created)".

## Page Actions

**Add Permission Set** opens a drawer for building a new set. Give the set a name, then use the permission builder to choose the permissions it should contain. Microsoft Graph is added as the default service principal, and further service principals can be added as needed. Some service principals publish no permissions at all, and so offer nothing to select.

## Table Details

| Column        | Description                                                                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Template Name | The name given to the permission set, used when selecting it during application deployment.                                                             |
| Permissions   | The permissions held in the set. The cell is a button showing how many entries are stored; selecting it opens the stored permission data in a dialog. |
| Updated By    | The CIPP user who last saved the set. Sets written by CIPP itself rather than by a person show as `CIPP-API`.                                           |
| Timestamp     | When the set was last saved.                                                                                                                            |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Permission Set</td><td>Opens the selected permission set in a drawer so its name and permissions can be changed.</td><td>true</td></tr><tr><td>Copy Permission Set</td><td>Opens the Add Permission Set page with the selected set's name and permissions pre-filled, ready to be saved under a new name.</td><td>false</td></tr><tr><td>Delete Permission Set</td><td>Deletes the selected permission set(s), after a confirmation prompt naming the set.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Editing a permission set changes it for every application template that references it. The change does not reach tenants on its own: applications already deployed keep the permissions they were granted until the template is deployed again. Deleting a set leaves any template referencing it without its permissions.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
