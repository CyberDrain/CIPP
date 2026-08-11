# Application Approval

The Application Approval wizard grants admin consent for an application across one or more customer tenants in a single pass, so your users are not left raising individual consent requests. Deploy from an app approval template, which carries a predefined permission set, or configure the application manually by its application ID.

{% hint style="info" %}
If you need an application deployed to every tenant and kept that way, use the App Approval standard instead. This wizard is a one-off action against the tenants you pick, and does not remediate tenants added later. See [standards](../../tenant/standards/ "mention").
{% endhint %}

{% stepper %}
{% step %}
### Tenant Selection

Choose the tenants to approve the application for. The selector accepts multiple tenants, and there is no All Tenants option on this page.
{% endstep %}

{% step %}
### App Selection

Choose an **Application Configuration Mode**, either **Use App Approval Template** (the default) or **Manual Configuration**.

**Use App Approval Template** deploys one of your saved app approval templates. Pick one from **Select App Template**, which is required to continue. Once selected, a **Template Details** card summarizes what will be deployed:

| Field          | Description                                                                                                                                                                                  |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App Name       | The display name recorded on the template.                                                                                                                                                   |
| App ID         | The application ID that will be approved in each tenant.                                                                                                                                     |
| Template Type  | Whether the template deploys an enterprise app, a gallery template or an application manifest.                                                                                               |
| Permission Set | The named permission set attached to the template. Gallery templates show **Auto-Consent** and manifest templates show **Defined in Manifest**, as neither draws on a stored permission set. |

Below the card, a preview shows exactly what is being consented to, in a form that depends on the template type. Review it before continuing.

**Manual Configuration** approves an application by ID without a template:

| Field                                          | Description                                                                                                                                                                                                       |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Application ID                                 | The application ID to approve. Must be a valid GUID.                                                                                                                                                              |
| Copy permissions from the existing application | Enabled by default. CIPP reads the permissions already configured on this application in your partner tenant and reproduces them in each selected tenant. The application must exist in the partner tenant first. |
| Permissions                                    | Only shown when the copy switch is turned off. Select the individual permissions to request from the list of available Microsoft Graph permissions.                                                               |

{% hint style="warning" %}
Selecting permissions by hand applies Microsoft Graph permissions only. If the application needs permissions on any other resource API, leave **Copy permissions from the existing application** enabled, or use a template.
{% endhint %}
{% endstep %}

{% step %}
### Confirmation

Review the summary of the tenants and application settings. If everything is correct, click **Submit**.
{% endstep %}
{% endstepper %}

## Template Types

App approval templates come in three types, and the wizard previews each differently:

| Type                 | Preview                                                                                                                                                                                                                                                                             |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enterprise App       | **Template Permissions**, showing the application and delegated permission counts and the full list grouped by resource API. Tabs let you view all permissions together or filter to application or delegated only, and each permission is listed with its resource application ID. |
| Gallery Template     | **Gallery Template Info**, showing the publisher, description, categories, supported single sign-on modes and supported provisioning types for the gallery application. Consent is handled by the gallery template itself rather than an explicit permission list.                  |
| Application Manifest | **Application Manifest**, showing the manifest that defines the application and the permissions it requests.                                                                                                                                                                        |

Templates are created and maintained separately:

## Deployment

Submitting queues one task per selected tenant rather than running the approval immediately, so the wizard returns straight away while deployment continues in the background. A confirmation message names the application and the tenants it is being deployed to.

Progress and any per-tenant failures are recorded in the logbook, which is where you should check the outcome rather than the wizard itself:

{% content-ref url="../../cipp/logs/" %}
[logs](../../cipp/logs/)
{% endcontent-ref %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
