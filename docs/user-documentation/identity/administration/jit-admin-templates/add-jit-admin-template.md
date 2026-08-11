# Add JIT Admin Template

This page creates a JIT Admin template, which stores the settings for a just-in-time admin grant so the same elevation can be requested repeatedly without rebuilding it. Templates are selected on the [add.md](../jit-admin/add.md "mention") page, and everything a template fills in can still be changed before the grant is submitted.

{% hint style="info" %}
The template is created for the tenant selected in the top menu; there is no tenant field on the form. Select All Tenants before opening this page to create a template available everywhere.
{% endhint %}

## Template Information

| Field              | Description                                                                                                                                                    |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Template Name      | The name the template is listed under. Required.                                                                                                               |
| Default for Tenant | Applies this template automatically when the JIT admin form is opened for this tenant. A tenant-specific default takes precedence over an All Tenants default. |

## Default JIT Admin Settings

**Admin Roles** and **Group Membership** are switches, and each reveals its own selector. At least one has to be turned on, and the form says so until one is.

| Field                        | Description                                                                                                                         |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Default Roles                | The Entra ID directory roles the template assigns.                                                                                  |
| Default Groups               | The groups the account is added to. Not available on an All Tenants template, since group identifiers do not carry between tenants. |
| Default Duration             | How long the elevation lasts, which sets the end date on the JIT admin form. Optional.                                              |
| Default Expiration Action    | What happens to the account when the elevation ends. Required.                                                                      |
| Default Notification Actions | Which channels are notified when the grant is created: Webhook, Email or PSA. Several can be selected.                              |
| Generate TAP by Default      | Issues a Temporary Access Pass with the grant.                                                                                      |
| Reason Template              | Reason text the template pre-fills, which the requester can adjust.                                                                 |

The duration list offers 1 hour, 4 hours, 8 hours, 1 day, 3 days, 7 days, 14 days and 30 days. A value of your own can be typed instead, in [ISO 8601](https://iso8601.com/) duration format, so `PT2H30M` gives two and a half hours and `P1D` gives a day.

The expiration action offers **Delete User** and **Disable User** whatever the switches are set to. It also offers **Remove Roles**, **Remove Groups** or **Remove Roles and Groups**, matching whichever switches are on, so the account survives and only the elevation is taken away. Changing the switches after choosing clears the selection, since the option may no longer apply.

## User Creation Settings

**Default User Action** decides whether the template creates a new account or elevates an existing one, and which fields follow.

| Field                                 | Description                                                                                                                              |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Default First Name, Default Last Name | The new account's name. Shown for a new user, and optional.                                                                              |
| Default Username                      | The part before the @ symbol. Shown for a new user, and optional.                                                                        |
| Default Domain                        | The domain the account is created under. Shown for a new user, and not available on an All Tenants template.                             |
| Default Usage Location                | The country the account is licensed in. Shown for a new user, and optional.                                                              |
| Default User                          | The account the elevation is granted to. Shown when the template targets an existing user, and not available on an All Tenants template. |

{% hint style="warning" %}
An All Tenants template can only create a new user. The Existing User option is not offered, because a specific account exists in one tenant and means nothing in the others. Domain and group selection are withdrawn for the same reason, so an All Tenants template covers the roles, timing and expiry behavior while the tenant-specific details are supplied when the grant is made.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
