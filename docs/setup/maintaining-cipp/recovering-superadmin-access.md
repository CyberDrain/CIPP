# Recovering Superadmin Access

## Recovering Superadmin Access

CIPP never lets you remove the last user with a manually assigned superadmin role, but that user can still become unavailable, for example when they leave the organisation or their account is deleted. A self-hosted instance on the new infrastructure keeps its user list in its own storage account, so you can restore a superadmin there from the Azure portal without signing in to CIPP.

{% stepper %}
{% step %}
### Open the allowedUsers table

In the Azure portal, open the storage account in your CIPP resource group, then go to **Storage browser** -> **Tables** -> `allowedUsers`.
{% endstep %}

{% step %}
### Find or add the user

Look for the row with a **PartitionKey** of `User` and a **RowKey** of the user's UPN in lowercase. Edit it if it exists, or select **Add entity** if it does not. For a guest user, use their email address as the RowKey.
{% endstep %}

{% step %}
### Set the properties

Set each property below with a type of **String**, entering the brackets and quotes exactly as shown.

| Property     | Value                                                       |
| ------------ | ----------------------------------------------------------- |
| PartitionKey | `User`                                                      |
| RowKey       | The user's UPN in lowercase, for example `user@contoso.com` |
| Roles        | `["superadmin"]`                                            |
| ManualRoles  | `["superadmin"]`                                            |
| AutoRoles    | `[]`                                                        |
| Source       | `Manual`                                                    |

The role name is exactly `superadmin`, in lowercase, and it must appear in both **Roles** and **ManualRoles**. **Roles** decides what the user can do, and **ManualRoles** is what CIPP counts when protecting the last superadmin.

If the user is also a member of an Entra group mapped on the [cipp-roles](../../user-documentation/cipp/advanced/authentication/cipp-roles/ "mention") page, the next user sync adds their group roles back and changes **Source** to `Both`.
{% endstep %}

{% step %}
### Save and wait for the change to apply

Save the entity. CIPP picks up the change at the next user sync, which runs every 15 minutes. Restarting the CIPP Web App applies it straight away.
{% endstep %}

{% step %}
### Confirm access

Sign in as the user and open [cipp-users.md](../../user-documentation/cipp/advanced/authentication/cipp-users.md "mention"). The user should be listed with a **Source** of Manual and the superadmin role. While you are there, assign superadmin manually to a second user so a single departure cannot lock you out again.
{% endstep %}
{% endstepper %}

{% hint style="warning" %}
Superadmin granted through an Entra group does not count as a manual superadmin, because group membership can change. Keep at least two users with superadmin assigned by hand on the CIPP Users page.
{% endhint %}
