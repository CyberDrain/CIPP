# View App Registration

This page shows a single app registration in detail: how it is configured, the credentials it holds, who owns it, whether a service principal exists for it in the tenant, and the API permissions its manifest requests.

The header carries the application's display name, chips for the Application (client) ID and Object ID that copy to the clipboard when selected, how long ago the registration was created, and a **View in Entra** link that opens the same registration in the Microsoft Entra admin center.

Unlike most tables in CIPP, this page always reads live from Microsoft Graph rather than from cache, so credential, redirect URI and audience changes made here are reflected as soon as they are applied.

## Page Actions

The actions menu offers the same actions as the [#table-actions](./#table-actions "mention") table, with the exception of the one that opens this page, along with two that appear only here.

| Action                | Description                                                                                                                                                                                                             |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Edit App Registration | Opens the app registration's branding and properties settings in the Microsoft Entra admin center, in a new tab.                                                                                                        |
| Edit Authentication   | Opens a form to change the supported account types and the web, single-page application and public client redirect URIs. Only the values you actually change are submitted, so audience and URI edits stay independent. |

{% hint style="info" %}
Selecting an account type that includes personal Microsoft accounts also sets the application's requested access token version to 2 in the same update, because those audiences only accept v2 tokens and Graph rejects the change otherwise.
{% endhint %}

## View App Registration Tab

### Application Details

This card identifies the registration. The top of the card shows the display name and sign-in audience, followed by the details below.

| Field                   | Description                                                                                                                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name            | The name of the application as registered in the tenant.                                                                                                                      |
| Application (client) ID | The application ID, shared by every service principal for this application across all tenants.                                                                                |
| Object ID               | The object ID of the application object itself, used for management calls against the registration.                                                                           |
| Sign-in Audience        | Which account types the application accepts, for example `AzureADMyOrg` for single-tenant or `AzureADMultipleOrgs` for multi-tenant.                                          |
| Publisher Domain        | The verified publisher domain recorded against the application.                                                                                                               |
| Disabled by Microsoft   | Whether Microsoft has disabled the application, and why. Applications in good standing show no value here.                                                                    |
| Created Date            | When the app registration was created.                                                                                                                                        |
| Redirect URI Count      | How many web redirect URIs are configured. This counts the web platform only, so applications using single-page application or public client URIs can legitimately show zero. |

### Credentials

Two collapsible entries summarize the credentials on the registration, one for client secrets and one for certificates. Each shows how many credentials are configured and the next expiry date, taken from the earliest expiry across all credentials of that type. Expanding an entry lists each credential by name and expiry date along with its key ID.

**Add secret** creates a new client secret directly from the secrets entry, taking a description and an expiry of 3, 6, 12 or 24 months or a custom date. Each credential also carries its own menu:

| Action | Description                                                                                                                            |
| ------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| Rotate | Creates a replacement client secret with the same name and a twelve month lifetime, then deletes the current one. Client secrets only. |
| Remove | Deletes the selected credential immediately, after a confirmation prompt.                                                              |

{% hint style="warning" %}
The value of a new or rotated secret is shown once, with a copy button, and cannot be retrieved afterwards. Rotation deletes the original as soon as the replacement exists, so anything still using the old value stops working until it is updated. Where the tenant enforces an application secret lifetime policy, the expiry is shortened to fit and you are told so in the result.
{% endhint %}

{% hint style="info" %}
Certificates can be removed here but not added. Upload a new certificate credential in Entra instead.
{% endhint %}

### Owners

Lists the owners of the app registration, with their display name, user principal name, mail address and object type. **View User** opens the selected owner in CIPP, and is offered only for owners that are users rather than groups or other service principals. Where Graph returns no owners the section says so, and where the request fails the error returned by Graph is shown instead.

### Enterprise App

Lists the service principals in the current tenant that share this application's client ID, with their display name, object ID, owning organization ID and service principal type.

A registration with no service principal has not been consented to or provisioned in the tenant yet, which is normal for an application that has only just been created. Where more than one is returned, the section lists them all.

### Application Manifest

A rendered view of the registration's manifest, showing its display name and description, sign-in audience, and web redirect URIs, followed by the permissions the manifest requests. Permissions are grouped by the API that publishes them, with a count of application and delegated permissions, and expanding a group lists each permission by name with the description published by that API.

## Permissions Tab

This tab presents the same `requiredResourceAccess` from the registration's manifest in more depth, split by permission type. These are the permissions the application asks for, which is not the same as what has been consented to in any given tenant.

### Application permissions

App-only permissions requiring admin consent, grouped by resource API. Each group is headed by the API name, its application ID and the number of permissions requested. Expanding a group lists each permission by name with its published description.

### Delegated permissions

Permissions exercised on behalf of a signed-in user, requiring user or admin consent, grouped by resource API in the same way.

### Risk indicators

Permissions that appear in CIPP's curated set of risky permissions are marked with a colored bar and a chip reading Critical, High, Medium or Low, with the reason shown on hover. Each API group carries a chip showing the highest risk found within it and how many of its permissions are flagged.

{% hint style="info" %}
Permission names and descriptions are resolved by looking up each resource API's service principal in the current tenant. Where an API has no service principal present, the group shows a warning and its permissions are listed as raw GUIDs until the API is provisioned in the tenant.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
