# Edit Tenant

This page shows the details CIPP holds for the currently selected tenant, along with the tenant-specific settings you can change: its alias and group membership, its offboarding defaults, and its custom variables.

{% hint style="info" %}
A specific tenant must be selected. With All Tenants selected, the page prompts you to choose a tenant instead.
{% endhint %}

## Tenant Details

Read-only details pulled from the tenant. Use the refresh button in the card header to fetch current values. Any field without a value is hidden rather than shown empty.

| Field             | Description                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------------- |
| Display Name      | The tenant's name as recorded in Entra ID.                                                  |
| Tenant ID         | The tenant's directory ID.                                                                  |
| Default Domain    | The tenant's default domain name.                                                           |
| Created           | When the tenant was created.                                                                |
| Address           | The tenant's registered address, combining street, city, state, postal code and country.    |
| Business Phone    | The business phone number recorded for the tenant.                                          |
| Technical Contact | The addresses Microsoft uses for technical notifications.                                   |
| On-Premises Sync  | The time of the last directory synchronisation, or Disabled where the tenant is cloud-only. |

## Edit Tenant Properties

Changes made here are saved with **Save Changes** and apply immediately across CIPP.

| Field        | Description                                                                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Alias | A custom name shown in place of the tenant's display name throughout CIPP. Useful where the registered organization name differs from the name you know the client by. |
| Add Group    | Adds the tenant to a static tenant group. Groups the tenant already belongs to, and dynamic groups, are not offered.                                                   |

The group list below shows each group's Name, Description and Group Type. Use the Remove action to take the tenant out of a group. Dynamic groups cannot be removed here because membership is determined by the group's own rules.

## Tenant Offboarding Defaults

These settings pre-select the offboarding options used when a user in this tenant is offboarded, and they take precedence over the defaults configured at user level. They set the starting position for the offboarding run rather than performing any action themselves, so each option can still be changed at the time of offboarding.

| Setting                                       | Description                                                                                                              |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Convert to Shared Mailbox                     | Converts the leaver's mailbox to a shared mailbox so colleagues can be granted access to it.                             |
| Remove from all groups                        | Removes the user from every group they are a member of.                                                                  |
| Hide from Global Address List                 | Hides the mailbox so it no longer appears in address lists.                                                              |
| Remove Licenses                               | Removes all licenses assigned to the user.                                                                               |
| Cancel all calendar invites                   | Cancels meetings the user organized so attendees are not left with orphaned invitations.                                 |
| Revoke all sessions                           | Invalidates existing sign-in sessions and refresh tokens, signing the user out everywhere.                               |
| Remove users mailbox permissions              | Removes the permissions the user held over other mailboxes.                                                              |
| Remove users calendar permissions             | Removes the permissions the user held over other calendars.                                                              |
| Remove all Rules                              | Deletes the inbox rules on the user's mailbox, including any forwarding rules.                                           |
| Reset Password                                | Sets the account password to a new random value.                                                                         |
| Keep copy of forwarded mail in source mailbox | Where forwarding is configured during offboarding, retains a copy of each forwarded message in the leaver's mailbox.     |
| Delete user                                   | Deletes the user account.                                                                                                |
| Remove all Mobile Devices                     | Removes the mobile devices registered against the user.                                                                  |
| Disable Sign in                               | Blocks the account from signing in while leaving it in place.                                                            |
| Remove all MFA Devices                        | Removes the user's registered authentication methods.                                                                    |
| Remove Teams Phone DID                        | Releases the phone number assigned to the user in Teams.                                                                 |
| Clear Immutable ID                            | Clears the immutable ID, which is needed where the account is to be rematched or moved out of directory synchronisation. |
| Disable OneDrive Sharing Links                | Disables the sharing links the user created from their OneDrive.                                                         |

Under **Send results to**, choose where the outcome of an offboarding run is reported: Webhook, E-mail, or PSA.

To clear the defaults for this tenant, use **Reset All to Off** and then **Save Changes**. Offboarding then falls back to the user-level defaults.

## Custom Variables

Custom variables are key-value pairs holding information specific to this tenant, applied to templates in standards using the format `%variablename%`. For example, you may need to set a client's RMM site ID. A variable set here takes precedence over a [global-variables.md](../administration/tenants/global-variables.md "mention") variable of the same name.

{% hint style="warning" %}
Where a variable is used in a template deployed through Standards, give it a global value as well as the per-tenant values. A variable defined only on some tenants is left unresolved on the rest, which causes the deployment to fail for those tenants. See [global-variables.md](../administration/tenants/global-variables.md "mention") for how this failure appears.
{% endhint %}

Use **Add Variable** to create one. The name picker offers variables already defined elsewhere, so reusing an existing name is easier than retyping it, and the type is set to match the existing definition. Reserved names and names already defined on this tenant are rejected.

### Table Details

| Column        | Description                                                                                                                                                                                                           |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Row Key       | The variable name, used in templates as `%variablename%`.                                                                                                                                                             |
| Value         | The value substituted into templates for this tenant.                                                                                                                                                                 |
| Scope         | Where the value comes from. Tenant is a variable defined only on this tenant, Global is inherited from the global list, and Overridden is a tenant value replacing a global one of the same name.                     |
| Variable Type | How the value is written into a template. String is the default and reproduces the original behavior. Integer, Boolean and JSON are written as raw JSON values, so a numeric setting receives 300 rather than "300". |
| Description   | The optional note recorded against the variable.                                                                                                                                                                      |

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit</td><td>Changes the value, type or description of the variable. Global variables cannot be edited from a tenant, only overridden.</td><td>false</td></tr><tr><td>Override for this tenant</td><td>Gives an inherited global variable a value that applies only to this tenant. Available on rows with a Global scope.</td><td>false</td></tr><tr><td>Revert to global</td><td>Removes this tenant's own value so the global value applies again. Available on rows with an Overridden scope.</td><td>false</td></tr><tr><td>View usage</td><td>Opens a flyout listing every tenant the variable is defined on, its value and type in each place, and a warning where the same name has been given different types.</td><td>false</td></tr><tr><td>Delete</td><td>Deletes the variable from this tenant. Not offered on inherited or overridden rows, which use Revert to global instead.</td><td>true</td></tr></tbody></table>

{% hint style="info" %}
If you want to see how to combine Custom Variables and Tenant Groups to provide a way to "graduate" tenants through standards, see [#using-custom-variables-to-manage-standards-templates](../../../demos/tutorials.md#using-custom-variables-to-manage-standards-templates "mention").
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
