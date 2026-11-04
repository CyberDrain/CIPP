# App Registrations

App registrations are the applications registered in the selected tenant, meaning the application objects the tenant itself owns. This is the definition of an application: its identifiers, sign-in audience, redirect URIs, requested permissions, and any secrets or certificates it holds. Applications consented to in the tenant but owned elsewhere appear under [enterprise-apps](../enterprise-apps/ "mention") instead.

The table is read live from Microsoft Graph each time the page loads.

## Sign-in Activity

With a single tenant selected, four columns show whether each application is still in use. They are read from CIPP's cache of the Entra sign-in activity reports, which needs Entra ID P1 and is collected with the nightly cache run, so they can be up to a day behind.

| Column                  | Shows                                                                                                                                                                                                        |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sign In Activity        | Active (signed in within 30 days), Idle 30+ days, Stale 90+ days, or No sign-in recorded. Measured from when the report was collected. Unknown (not collected) when the tenant's report has not been cached. |
| Last Sign In Date Time  | The last sign-in in this tenant through the application's enterprise app, delegated or app-only.                                                                                                             |
| Credential Use          | Whether the application's unexpired secrets and certificates have signed in during the last 90 days: All used in 90 days, Unused credentials (with how many of them), or No active credentials.              |
| Last Credential Sign In | The most recent sign-in by any of its secrets or certificates.                                                                                                                                               |

The **Stale (no sign-in for 90+ days)**, **No sign-in recorded** and **Unused credentials (90+ days)** filters use these columns. An unused credential is a good candidate for removal, since nothing has signed in with it. Check with the application's owner first: a credential kept for a rarely run job looks the same.
## Table Details

The properties returned are for the Graph resource type `application`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/application?view=graph-rest-1.0#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View in CIPP</td><td>Opens the <a data-mention href="appid.md">appid.md</a> page for the selected app registration.</td><td>false</td></tr><tr><td>View App Registration</td><td>Opens the selected app registration in the Microsoft Entra admin center, in a new tab.</td><td>false</td></tr><tr><td>View API Permissions</td><td>Opens the API permissions view for the selected app registration in the Microsoft Entra admin center, in a new tab.</td><td>false</td></tr><tr><td>Create Enterprise App Template (Multi-Tenant)</td><td>Creates a reusable Enterprise App template from the selected app registration, copying its permissions into an automatically created permission set. Run from a customer tenant, the app registration is first copied to the partner tenant as a multi-tenant app. An option is offered to overwrite an existing template of the same name. Only available for multi-tenant applications that were not created from a gallery template.</td><td>true</td></tr><tr><td>Create Manifest Template (Single-Tenant)</td><td>Captures the application manifest into a named template that can then be deployed to any tenant. Credentials, tenant-specific identifiers and the publisher domain are stripped before the template is saved. Only available for single-tenant applications that were not created from a gallery template.</td><td>true</td></tr><tr><td>Add Client Secret</td><td>Creates a new client secret on the selected app registration, with a description of your choosing and an expiry of 3, 6, 12 or 24 months or a custom date. The secret value is shown once when it is created, with a copy button.</td><td>true</td></tr><tr><td>Remove Password Credentials</td><td>Prompts you to choose which of the application's client secrets to remove, listed by name and expiry date, then removes only those selected. Only available where the application holds password credentials.</td><td>true</td></tr><tr><td>Remove Certificate Credentials</td><td>Prompts you to choose which of the application's certificate credentials to remove, listed by name and expiry date, then removes only those selected. Only available where the application holds certificate credentials.</td><td>true</td></tr><tr><td>Add Federated Credential</td><td>Lets tokens from another identity provider sign in as the selected app registration with no secret: GitHub Actions for a repository environment, branch, tag or pull requests, a Kubernetes service account, a managed identity in this tenant, or any other OpenID Connect issuer and subject. See <a data-mention href="appid.md">appid.md</a> for the fields.</td><td>true</td></tr><tr><td>Remove Federated Credentials</td><td>Prompts you to choose which of the application's federated credentials to remove, listed by name, issuer and subject, then removes only those selected.</td><td>false</td></tr><tr><td>Delete App Registration</td><td>Deletes the selected app registration(s). Anything authenticating as the application stops working immediately.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
The two template actions are mutually exclusive: which one a row offers depends on its sign-in audience, so any given application shows one or the other rather than both. Templates created either way are saved to templates and can be deployed from there.
{% endhint %}

{% hint style="warning" %}
Where the tenant enforces an application secret lifetime policy, the expiry you choose for a new client secret is shortened to fit and you are told so in the result. The secret value cannot be retrieved after the dialogue closes, so copy it before dismissing it. **Add Client Secret** is available in bulk, but a bulk run creates a separate secret on every selected application, so use it one application at a time when you need to keep the values.
{% endhint %}

## Extended Info Flyout

Alongside the usual row details, the flyout for this table renders an **Application Manifest** preview of the selected app registration:

* The display name and description, its sign-in audience, and its web redirect URIs.
* The permissions the application requests, grouped by the API that publishes them. Each group shows a count of application and delegated permissions, and expanding it lists each one by name with the description published by that API.

These are the permissions the application asks for in its manifest, which is not the same as what has been consented to in a tenant. Granted consent is shown on the Permissions tab of ...

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
