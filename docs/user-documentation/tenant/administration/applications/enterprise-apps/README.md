# Enterprise Applications

Enterprise applications are the service principals present in the selected tenant: every application that has been granted a presence there, including Microsoft first-party services, third-party SaaS apps that users or admins have consented to, and any partner applications such as CIPP's own SAM app. Listing them is the quickest way to audit what has access to a tenant, spot applications carrying client secrets or certificates, and identify leftover integrations from a previous provider.

The table is read live from Microsoft Graph each time the page loads, so it always reflects the tenant's current state.

{% hint style="info" %}
Microsoft first-party service principals make up the bulk of a typical tenant's list. Sort or filter on **Publisher Name** to bring third-party and partner applications to the top.
{% endhint %}

## Page Actions

**Deploy Template** opens [appapproval.md](../../../../tools/tenant-tools/appapproval.md "mention"), where a saved application template can be deployed to one or more tenants.

## Filters

| Filter                       | Shows                                                     |
| ----------------------------- | --------------------------------------------------------- |
| Hidden from MyApps portal    | Applications currently hidden from users in the MyApps portal. |

The **Graph filters** group in the Filters menu changes the request sent to Microsoft Graph rather than filtering the rows already loaded. See [table-features.md](../../../../shared-features/table-features.md "mention") for how the two kinds of filter combine.

| Graph filter                  | Shows                                                     |
| ----------------------------- | --------------------------------------------------------- |
| All Enterprise Applications   | Applications tagged as integrated Microsoft Entra applications. |
| SAML Applications             | Gallery applications, which is where SAML single sign-on applications are found. |
| Connectwise Breached Apps     | Any of the four ConnectWise Cloud Management applications named in the ConnectWise breach disclosure that exist in the tenant. Set the tenant selector to **All Tenants** to check every tenant at once. To be told when one appears, use the **Alert on presence of specific app ids** alert on [alert.md](../../alert-configuration/alert.md "mention"). |

## Table Details

The properties returned are for the Graph resource type `servicePrincipal`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipal?view=graph-rest-1.0#properties).

The password and certificate credential columns are included so that applications holding secrets or certificates, and their expiry dates, can be reviewed without opening each application in turn.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View in CIPP</td><td>Opens the <a data-mention href="spid.md">spid.md</a> page for the selected enterprise application.</td><td>false</td></tr><tr><td>View Application</td><td>Opens the selected enterprise application in the Microsoft Entra admin center, in a new tab.</td><td>false</td></tr><tr><td>Create Template from App</td><td>Creates a reusable Enterprise App template from the selected application and copies its permissions into a permission set, both named "&#x3C;application name> (Auto-created)". An option is offered to overwrite an existing template of the same name. Greyed out unless the application is multi-tenant; single-tenant applications need a manifest template created from the App Registrations page instead.</td><td>true</td></tr><tr><td>Remove Password Credentials</td><td>Prompts you to choose which of the application's client secrets to remove, listed by name and expiry date, then removes only those selected. Greyed out unless the application holds password credentials.</td><td>true</td></tr><tr><td>Remove Certificate Credentials</td><td>Prompts you to choose which of the application's certificate credentials to remove, listed by name and expiry date, then removes only those selected. Greyed out unless the application holds certificate credentials.</td><td>true</td></tr><tr><td>Disable Service Principal</td><td>Blocks sign-in to the selected application without removing it or its consent. Greyed out unless the service principal is currently enabled.</td><td>true</td></tr><tr><td>Enable Service Principal</td><td>Restores sign-in for a previously disabled application. Greyed out unless the service principal is currently disabled.</td><td>true</td></tr><tr><td>Hide from MyApps portal</td><td>Removes the application from the MyApps portal so users no longer see it listed there. Greyed out where the application is already hidden.</td><td>true</td></tr><tr><td>Show in MyApps portal</td><td>Restores the application's visibility in the MyApps portal. Greyed out unless the application is currently hidden.</td><td>true</td></tr><tr><td>Delete Service Principal</td><td>Removes the application from the tenant, revoking its access and any consent granted to it. The app registration in the application's home tenant is not affected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Actions you do not have permission for stay in the menu but are greyed out. Everything except View in CIPP, View Application and More Info needs the `Tenant.Application.ReadWrite` permission.
{% endhint %}

{% hint style="warning" %}
Removing credentials, disabling, or deleting a service principal takes effect immediately and will break any integration currently authenticating as that application. Confirm what an application is used for before acting on it, particularly for applications published by your own or another partner organisation.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
