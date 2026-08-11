# View Enterprise Application

This page shows a single enterprise application in detail: its identifiers and publisher, the credentials it holds, who owns it, and the permissions that have actually been granted to it in the tenant.

The header carries the application's display name, chips for the Application (client) ID and Object ID that copy to the clipboard when selected, how long ago the service principal was created, and a **View in Entra** link that opens the same application in the Microsoft Entra admin center.

## Page Actions

The actions menu offers the same actions as the [#table-actions](./#table-actions "mention") table, with the exception of the one that opens this page. All of them act on the application currently in view.

## View Enterprise App Tab

### Enterprise application

This card identifies the application. The top of the card shows the display name and whether the service principal is enabled or disabled, followed by the details below.

| Field                   | Description                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Display name            | The name of the application as it appears in the tenant.                                                                             |
| Application (client) ID | The application ID, shared by every service principal for this application across all tenants.                                       |
| Object ID               | The object ID of the service principal, unique to this tenant.                                                                       |
| Sign-in audience        | Which account types the application accepts, for example `AzureADMyOrg` for single-tenant or `AzureADMultipleOrgs` for multi-tenant. |
| Publisher               | The publisher name recorded against the application, where one is set.                                                               |
| Homepage                | The application's home page URL, where one is set.                                                                                   |
| Created                 | When the service principal was created in this tenant.                                                                               |

**Open app registration in CIPP** opens [appid.md](../app-registrations/appid.md "mention") for the same application ID.

{% hint style="info" %}
An app registration only exists in the tenant that owns the application. For Microsoft services and third-party multi-tenant applications, the registration lives in the publisher's tenant, so the app registration page will not find it.
{% endhint %}

### Credentials

Two collapsible entries summarize the credentials held by the service principal, one for client secrets and one for certificates. Each shows how many credentials are configured and the next expiry date, taken from the earliest expiry across all credentials of that type.

Expanding an entry lists each credential individually by name and expiry date, along with its key ID. Where the credential list is empty, the entry is marked in amber to draw the eye; that is a prompt to check rather than a fault, since most applications legitimately hold no credentials in the tenants they are consented to.

Each credential carries its own menu:

| Action | Description                                                                                                                                                                                    |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rotate | Creates a replacement client secret with the same name and a twelve month lifetime, then deletes the current one. The new secret value is shown once, with a copy button. Client secrets only. |
| Remove | Deletes the selected credential immediately, after a confirmation prompt.                                                                                                                      |

{% hint style="warning" %}
Rotation deletes the original secret as soon as the replacement is created, so anything still using the old value stops working until it is updated. Copy the new secret before closing the dialog, as it cannot be retrieved afterwards. Where the tenant enforces an application secret lifetime policy, the twelve month lifetime is shortened to fit and you are told so in the result.
{% endhint %}

{% hint style="info" %}
Credentials cannot be added from this page, only rotated or removed. A certificate removed here has to be uploaded again in Entra.
{% endhint %}

### Owners

Lists the directory objects that own the service principal, with their display name, user principal name, mail address and object type. **View User** opens the selected owner in CIPP, and is offered only for owners that are users rather than groups or other service principals.

Where Graph returns no owners the section says so, and where the owners request fails the error returned by Graph is shown instead. Microsoft first-party service principals routinely have no owners at all.

## Permissions Tab

This tab shows what the application has actually been granted in the tenant, read from the service principal's own app role assignments and OAuth2 permission grants. It reflects consent as it stands now, not what the application asks for in its manifest, so a permission the application requests but has never been consented to will not appear here.

### Application permissions

App roles assigned to the application for app-only access, grouped by the API that publishes them. Each group is headed by the resource name, its object ID, and the number of permissions granted. Expanding a group lists each permission by name with the description published by that API.

### Delegated permissions

OAuth2 permission grants where this application is the client, grouped by resource API in the same way. Scopes are de-duplicated and sorted across all grants for that resource, so a scope granted both tenant-wide and to an individual user appears once.

### Risk indicators

Permissions that appear in CIPP's curated set of risky permissions are marked with a colored bar and a chip reading Critical, High, Medium or Low. Hovering the chip gives the reason the permission is considered risky. Each API group carries a chip of its own showing the highest risk found within it and how many of its permissions are flagged.

{% hint style="info" %}
The risky-permissions set is a deliberately short list of the permissions most useful to an attacker, and it concentrates on application permissions, so delegated scopes are rarely flagged. A permission without a chip has not been assessed rather than judged safe.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
