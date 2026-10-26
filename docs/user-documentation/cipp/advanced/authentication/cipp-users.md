# CIPP Users

The CIPP Users page controls who can access CIPP and what they can do. Access is granted in two ways that work side by side. Users are automatically synced from your partner tenant every 15 minutes based on the Entra group memberships configured on the CIPP Roles page, and you can also add users or assign roles by hand. Manual assignments are held separately from the automatic sync, so they are never overwritten when the sync runs.

## Table Details

| Column | Description                                                                                                                         |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| UPN    | The user's email address (user principal name).                                                                                     |
| Roles  | The user's effective roles in CIPP.                                                                                                 |
| Source | How the user's access was assigned: Auto (synced from Entra groups), Manual (assigned by hand), or Both (a combination of the two). |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Roles</td><td>Opens a dialog to change the user's manually assigned roles. Auto-synced roles are managed by the sync and are not affected.</td><td>true</td></tr><tr><td>Delete User</td><td>Removes the user's access to CIPP.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

The Extended Info flyout breaks a user's access down further than the table does, showing their email, source, and last sync time, along with their roles split into three groups: the effective roles that apply, the manually assigned roles, and the auto roles inherited from Entra groups.

## Adding and Editing Users

Select **Add User** above the table to add someone by hand. Enter the user's email address (UPN) and assign one or more roles from the available CIPP roles. These are stored as manual assignments and are not overwritten by the automatic Entra group sync. A user who already exists cannot be added again; use Edit Roles to change their permissions instead.

The **Edit Roles** action changes the manually assigned roles for an existing user. Selecting several users first and then using Edit Roles opens a bulk edit dialog that sets the same manual roles across all of the selected users, replacing their existing manual roles. In every case, auto-synced roles from Entra groups are left untouched.

## Roles and Access

A few rules govern roles on this page:

* The **superadmin** role grants full access to CIPP. When a user has it, all of their other role assignments are ignored.
* There must always be at least one superadmin. You cannot remove the superadmin role from a user if they are the only superadmin. To hand the role over, assign superadmin to another user first, then remove it from the original.
* Only superadmin assigned by hand on this page counts towards that minimum. Superadmin inherited from an Entra group does not, because group membership can change.
* If no superadmin can sign in, a self-hosted instance can restore one from its storage account. See [#recovering-superadmin-access](../../../../setup/setting-up-cipp/roles.md#recovering-superadmin-access "mention").
* To grant access to users outside your partner tenant, either add them as guest users in your partner tenant and assign their roles here or enable multi-tenant mode on the CIPP SSO tab and add them to the list directly, without inviting them as guests.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
