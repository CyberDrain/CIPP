# NinjaOne

The NinjaOne integration pushes Microsoft 365 tenant, user, license and device information from CIPP into NinjaOne, and can monitor Intune device compliance as a NinjaOne custom field. Tenant and device data is written to NinjaOne custom fields, while detailed user and license records use NinjaOne Documentation. You control which of these are populated, so it is entirely reasonable to sync only the parts you need.

{% hint style="warning" %}
The NinjaOne CIPP integration requires NinjaOne version 5.6 or above.
{% endhint %}

{% hint style="info" %}
Tenant and device information uses custom fields, which you create yourself in NinjaOne. Detailed user and license information uses NinjaOne Documentation, and the document templates are created for you. If you do not have NinjaOne Documentation, speak to your account manager — the rest of the integration still works without it.
{% endhint %}

## Settings

| Setting                                                    | Description                                                                                                                                                                                                    |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                         | Turns the integration on. Every other setting, the **Test** and **Force Sync** buttons, and the **Tenant Mapping** and **Field Mapping** tabs remain unavailable until this is enabled and saved.              |
| Please enter your NinjaOne Instance hostname               | The hostname of your NinjaOne instance, such as `app.ninjarmm.com`, `eu.ninjarmm.com`, `oc.ninjarmm.com`, `ca.ninjarmm.com` or `us2.ninjarmm.com`. Enter the hostname only, without a scheme or trailing path. |
| NinjaOne API Client ID                                     | The Client ID of the API application created in NinjaOne.                                                                                                                                                      |
| NinjaOne API Client Secret                                 | The client secret of that application. Stored securely and masked once saved.                                                                                                                                  |
| Sync Licenses (Requires NinjaOne Documentation)            | Creates a document per license in each tenant, using a CIPP-managed document template.                                                                                                                         |
| Sync Users (Requires NinjaOne Documentation)               | Creates a document per user in each tenant, using a CIPP-managed document template.                                                                                                                            |
| Only Sync Licensed Users (Requires NinjaOne Documentation) | Restricts user synchronisation to users holding a license. This applies to both the user documents and the tenant-level user summary field.                                                                    |
| Enable Automated CVE Sync                                  | Uploads Defender vulnerability data to NinjaOne scan groups as part of each tenant synchronisation.                                                                                                            |
| CVE Sync Scan Group Prefix                                 | The prefix used to identify the scan groups CIPP maintains. Scan groups are named `[Prefix][tenant-domain]`, for example `CIPP-contoso.com`. Appears once automated CVE sync is enabled.                       |

## Preparing NinjaOne

{% stepper %}
{% step %}
### Create an API application

Sign in to NinjaOne as a System Administrator and go to **Administration** > **Apps** > **API**, then select **Add**.

Choose an **Application Platform** of _API Services (machine-to-machine)_, give it a name such as _CIPP Integration_, and leave **Redirect URIs** blank. Select the **Monitoring** and **Management** scopes, and an allowed grant type of **Client Credentials**. Save.

The client secret is shown once on save — record it before closing the application. The **Client ID** can be copied from the table afterwards.
{% endstep %}

{% step %}
### Create the custom fields

Tenant and device data is written to NinjaOne custom fields, which must exist before CIPP can write to them. Create only the fields you actually want populated.

Go to **Administration** > **Devices** > **Global Custom Fields** and select add. Enter a label of your choosing, leave the generated name as it is unless you have a reason to change it, select the type from the table below, and create the field.

On the following screen set the **Technician Permission** to _Read Only_, leave **Automations** set to None, and set the **API permission** to _Read/Write_. WYSIWYG fields can optionally be expanded by default under Advanced Settings. Repeat for each field you want.
{% endstep %}
{% endstepper %}

The fields available for mapping are:

| CIPP Field                      | Type    | Definition Scope | Description                                                                                                                          |
| ------------------------------- | ------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Microsoft 365 Tenant Links      | WYSIWYG | Organization     | Quick links from NinjaOne to the Microsoft 365 and CIPP portals for the tenant.                                                      |
| Microsoft 365 Tenant Summary    | WYSIWYG | Organization     | A summary overview of the Microsoft 365 tenant.                                                                                      |
| Microsoft 365 Users Summary     | WYSIWYG | Organization     | A table of users in the tenant with details such as OneDrive and Exchange usage and their associated devices.                        |
| Microsoft 365 Device Links      | WYSIWYG | Device           | Links from a device in NinjaOne to the corresponding Microsoft and CIPP pages.                                                       |
| Microsoft 365 Device Summary    | WYSIWYG | Device           | An overview of the device, including compliance status and group membership.                                                         |
| Intune Device Compliance Status | TEXT    | Device           | The device's current compliance state, written as `Compliant` or `Non-Compliant` so it can be watched with a custom field condition. |

{% hint style="warning" %}
A custom field only appears in CIPP's mapping dropdowns when its API permission is set to Read/Write and its type and definition scope match the table above. If a field is missing from the list, that is almost always why.
{% endhint %}

{% hint style="info" %}
Set the **Automations** permission to Read Only on the Intune Device Compliance Status field if you intend to drive a condition monitor from it. The other fields can be left with Automations set to None.
{% endhint %}

## Configuring the Integration in CIPP

{% stepper %}
{% step %}
### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
### Enter the connection details

Enter your instance hostname, then the **NinjaOne API Client ID** and **NinjaOne API Client Secret** from the API application you created.
{% endstep %}

{% step %}
### Choose what to synchronise

If you have NinjaOne Documentation, enable **Sync Users** and **Sync Licenses** as required, and **Only Sync Licensed Users** if you would rather not document unlicensed accounts.
{% endstep %}

{% step %}
### Save and test

Select **Submit**, then select **Test**. A message confirming a successful connection to NinjaOne means the credentials and hostname are correct.
{% endstep %}

{% step %}
### Map organizations and fields

Work through the **Tenant Mapping** and **Field Mapping** tabs described below. Nothing synchronises until at least the organization mapping is in place.
{% endstep %}
{% endstepper %}

## Organization Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a NinjaOne organization. Only mapped tenants are synchronised, so this is what determines the scope of the integration.

To map manually, choose a tenant, choose the NinjaOne organization under **Select NinjaOne Company**, and select the add button. **Automap Companies** matches automatically. Mappings are only written when you select **Submit**.

| Column          | Description                                                    |
| --------------- | -------------------------------------------------------------- |
| IntegrationName | The name of the NinjaOne organization the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant.           |
| TenantDomain    | The default domain name of the mapped tenant.                  |
| TenantId        | The tenant's Microsoft customer ID.                            |

Individual mappings can be removed with the **Delete Mapping** row action.

{% hint style="info" %}
Automapping works in two passes. It first matches tenants whose display name is identical to a NinjaOne organization name. Any tenant left over is then matched on hardware: CIPP compares Intune devices against NinjaOne devices by serial number and then by device name, and maps the tenant to whichever organization owns the matching devices. Devices with duplicate or placeholder serial numbers are ignored.

The second pass runs in the background and can take some time on a large estate. Refresh the page to pick up new matches, and check the CIPP logbook to see when it finishes. Tenants that are already mapped are never re-matched.
{% endhint %}

## Field Mapping

The **Field Mapping** tab connects each piece of CIPP data to the NinjaOne custom field that should hold it. Fields are grouped into **NinjaOne Organization Global Custom Field Mapping** and **NinjaOne Device Custom Field Mapping**, and each dropdown only offers NinjaOne fields of a compatible type and scope.

Choose a NinjaOne field for each item you want populated, and leave the rest set to `--- Do not synchronize ---`. Select **Submit** to save. The refresh button re-reads the custom field list from NinjaOne, which is worth using after creating new fields.

{% hint style="warning" %}
If a previously mapped NinjaOne field is deleted or its API permission is changed, CIPP flags the affected mapping as missing when the tab loads. Recreate the field or remap it, or that data will silently stop being written.
{% endhint %}

## What Gets Synchronised

A full synchronisation runs once every 24 hours for every mapped tenant. CIPP assigns each installation its own slot in the day rather than running everything at midnight, and tenants whose previous run did not complete are automatically picked up on a later pass.

Synchronisation can also be triggered on demand. **Force Sync** on this page queues every mapped tenant, and the Integration Sync page shows per-tenant status and allows a single tenant to be queued on its own.

Intune device compliance is handled separately. CIPP subscribes to Graph change notifications for device compliance, so the Intune Device Compliance Status field updates within minutes of a change in Microsoft 365 rather than waiting for the daily run. This requires the compliance field to be mapped.

Where **Sync Users** or **Sync Licenses** is enabled, CIPP creates and maintains the document templates it needs in NinjaOne Documentation — `CIPP - Microsoft 365 Users` and `CIPP - Microsoft 365 Licenses` — and writes a document per user or license beneath them. You do not need to create these templates yourself.

## CVE Synchronisation

With **Enable Automated CVE Sync** on, each tenant synchronisation uploads that tenant's Defender vulnerability data into a NinjaOne vulnerability scan group. This relies on CIPP already holding vulnerability data for the tenant, and on the scan group existing in NinjaOne under the expected name.

{% stepper %}
{% step %}
### Schedule vulnerability collection in CIPP

On the CVE Management page, select **Schedule CVE Sync**, choose a tenant or all tenants, set a frequency, and create the schedule. This is what populates the vulnerability data CIPP later uploads.
{% endstep %}

{% step %}
### Configure the prefix

Turn on **Enable Automated CVE Sync**, set the **CVE Sync Scan Group Prefix**, and select **Submit**. CIPP looks for a scan group named with this prefix followed by the tenant's default domain name.
{% endstep %}

{% step %}
### Create the scan groups in NinjaOne

On the Vulnerabilities page, select the tenant, then export the list to CSV.

In NinjaOne go to **Administration** > **Apps** > **Microsoft Defender**, open the **Scan Groups** tab and select **+ Create scan group**. Name it exactly as CIPP expects — the prefix followed by the tenant's default domain name — then upload the CSV and confirm the column mappings.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
CVE exceptions recorded in CIPP are applied before upload, both tenant-specific exceptions and those set for all tenants, so a suppressed CVE does not reappear in NinjaOne. If the expected scan group does not exist, that tenant's CVE upload is skipped and a warning is written to the CIPP logbook.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
