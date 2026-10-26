# NinjaOne

The NinjaOne integration pushes Microsoft 365 tenant, user, licence and device information from CIPP into NinjaOne, and can monitor Intune device compliance as a NinjaOne custom field. Tenant and device data is written to NinjaOne custom fields, while detailed user and licence records use NinjaOne Documentation. You control which of these are populated, so it is entirely reasonable to sync only the parts you need.

{% hint style="warning" %}
The NinjaOne CIPP integration requires NinjaOne version 5.6 or above.
{% endhint %}

{% hint style="info" %}
Tenant and device information uses custom fields, which you create yourself in NinjaOne. Detailed user and licence information uses NinjaOne Documentation, and the document templates are created for you. If you do not have NinjaOne Documentation, speak to your account manager: the rest of the integration still works without it.
{% endhint %}

## Settings

| Setting                                                    | Description                                                                                                                                                                                                    |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                         | Turns the integration on. Every other setting, the **Test** and **Force Sync** buttons, and the **Tenant Mapping** and **Field Mapping** tabs remain unavailable until this is enabled and saved.              |
| Please enter your NinjaOne Instance hostname               | The hostname of your NinjaOne instance, such as `app.ninjarmm.com`, `eu.ninjarmm.com`, `oc.ninjarmm.com`, `ca.ninjarmm.com` or `us2.ninjarmm.com`. Enter the hostname only, without a scheme or trailing path. |
| NinjaOne API Client ID                                     | The Client ID of the API application created in NinjaOne.                                                                                                                                                      |
| NinjaOne API Client Secret                                 | The client secret of that application. Stored securely and masked once saved.                                                                                                                                  |
| Sync Licenses (Requires NinjaOne Documentation)            | Creates a document per licence in each tenant, using a CIPP-managed document template.                                                                                                                         |
| Sync Users (Requires NinjaOne Documentation)               | Creates a document per user in each tenant, using a CIPP-managed document template.                                                                                                                            |
| Only Sync Licensed Users (Requires NinjaOne Documentation) | Restricts user synchronisation to users holding a licence. This applies to both the user documents and the tenant-level user summary field.                                                                    |
| Enable Automated CVE Sync                                  | Uploads Defender vulnerability data to NinjaOne scan groups as part of each tenant synchronisation.                                                                                                            |
| CVE Sync Scan Group Prefix                                 | The prefix used to identify the scan groups CIPP maintains. Scan groups are named `[Prefix][tenant-domain]`, for example `CIPP-contoso.com`. Appears once automated CVE sync is enabled.                       |

## Preparing NinjaOne

{% stepper %}
{% step %}
### Create an API application

Sign in to NinjaOne as a System Administrator and go to **Administration** > **Apps** > **API**, then select **Add**.

Choose an **Application Platform** of _API Services (machine-to-machine)_, give it a name such as _CIPP Integration_, and leave **Redirect URIs** blank. Select the **Monitoring** and **Management** scopes, and an allowed grant type of **Client Credentials**. Save.

The client secret is shown once on save, so record it before closing the application. The **Client ID** can be copied from the table afterwards.
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
| Intune Non-Compliant Settings   | TEXT_MULTILINE or TEXT | Device | One line per compliance policy setting the device currently fails, written as `Policy name: Setting name`. Cleared when the device is compliant, so a condition on the field not being empty flags only devices with a real failure. |

{% hint style="warning" %}
A custom field only appears in CIPP's mapping dropdowns when its API permission is set to Read/Write and its type and definition scope match the table above. If a field is missing from the list, that is almost always why.
{% endhint %}

{% hint style="info" %}
Set the **Automations** permission to Read Only on the Intune Device Compliance Status and Intune Non-Compliant Settings fields if you intend to drive a condition monitor from them. The other fields can be left with Automations set to None.
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
### Map organisations and fields

Work through the **Tenant Mapping** and **Field Mapping** tabs described below. Nothing synchronises until at least the organisation mapping is in place.
{% endstep %}
{% endstepper %}

## Organisation Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a NinjaOne organisation. Only mapped tenants are synchronised, so this is what determines the scope of the integration.

{% hint style="warning" %}
Saving on the **Tenant Mapping** and **Field Mapping** tabs requires a role with unrestricted tenant access, meaning **Allowed Tenants** left as `AllTenants` with nothing in **Blocked Tenants**. A role scoped to particular tenants or tenant groups can read the existing mappings but is refused when it selects **Submit** or **Automap Companies**. See [roles.md](../../../setup/setting-up-cipp/roles.md "mention").
{% endhint %}

To map manually, choose a tenant, choose the NinjaOne organisation under **Select NinjaOne Company**, and select the add button. **Automap Companies** matches automatically. Manual mappings are only written when you select **Submit**.

| Column          | Description                                                    |
| --------------- | -------------------------------------------------------------- |
| IntegrationName | The name of the NinjaOne organisation the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant.           |
| TenantDomain    | The default domain name of the mapped tenant.                  |
| TenantId        | The tenant's Microsoft customer ID.                            |

Each row also offers two actions: **Sync Now** queues an on-demand synchronisation for that tenant only, without waiting for the next scheduled run, and **Delete Mapping** removes the mapping.

{% hint style="info" %}
Automapping works in two passes. It first matches tenants whose display name is identical to a NinjaOne organisation name. Any tenant left over is then matched on hardware: CIPP compares the tenant's Intune devices against NinjaOne devices by serial number and then by device name, and maps the tenant to whichever organisation owns the most matching devices. The Intune devices come from CIPP's cached device data, so a tenant whose devices have not been cached yet can only match by name. Serial numbers or device names found in more than one organisation, placeholder serials, ties, and organisations that are already mapped are skipped.

Both passes run in the background and save their mappings immediately. Refresh the page to pick up new matches, and check the Logbook, which records a line for each mapping created. Tenants that are already mapped are never re-matched.

**Automap Companies** also suggests looser name matches that ignore case, punctuation and legal suffixes such as Ltd or LLC. Those appear in the table but are only saved when you select **Submit**.
{% endhint %}

{% hint style="info" %}
While the integration is enabled, CIPP also runs the name pass automatically every two hours, just before scheduling the NinjaOne synchronisation, so newly added tenants whose names match are mapped and synchronised without visiting this page. Hardware matching downloads every device in NinjaOne, so it only runs when you select **Automap Companies**.
{% endhint %}

## Field Mapping

The **Field Mapping** tab connects each piece of CIPP data to the NinjaOne custom field that should hold it. Fields are grouped into **NinjaOne Organization Global Custom Field Mapping** and **NinjaOne Device Custom Field Mapping**, and each dropdown only offers NinjaOne fields of a compatible type and scope.

Choose a NinjaOne field for each item you want populated, and leave the rest set to `--- Do not synchronize ---`. Select **Submit** to save. The refresh button re-reads the custom field list from NinjaOne, which is worth using after creating new fields.

{% hint style="warning" %}
If a previously mapped NinjaOne field is deleted or its API permission is changed, CIPP flags the affected mapping as missing when the tab loads. Recreate the field or remap it, or that data will silently stop being written.
{% endhint %}

## What Gets Synchronised

A full synchronisation runs once every 24 hours for every mapped tenant. CIPP assigns each installation its own slot in the day rather than running everything at midnight, and tenants whose previous run did not complete are automatically picked up on a later pass.

Synchronisation can also be triggered on demand. **Force Sync** on this page queues every mapped tenant, and the **Sync Now** row action on the **Tenant Mapping** table queues a single tenant on its own. NinjaOne runs its own synchronisation rather than using the scheduled integration tasks, so mapped tenants do not appear on the [integration-sync.md](integration-sync.md "mention") page.

Before the daily run, a catch-up pass, or **Force Sync** queues any tenants, CIPP checks that it can sign in to NinjaOne with the saved credentials. If it cannot, no tenants are queued and the logbook records that the NinjaOne API check failed. Select **Test** to confirm the credentials.

Intune device compliance is handled separately. CIPP subscribes to Graph change notifications for device compliance, so the Intune Device Compliance Status and Intune Non-Compliant Settings fields update within minutes of a change in Microsoft 365 rather than waiting for the daily run. This requires at least one of those two fields to be mapped.

Where **Sync Users** or **Sync Licenses** is enabled, CIPP creates and maintains the document templates it needs in NinjaOne Documentation, `CIPP - Microsoft 365 Users` and `CIPP - Microsoft 365 Licenses`, and writes a document per user or licence beneath them. You do not need to create these templates yourself.

## CVE Synchronisation

With **Enable Automated CVE Sync** on, every tenant synchronisation (the daily run, **Force Sync** or **Sync Now**) uploads that tenant's Defender vulnerability data into a NinjaOne vulnerability scan group. Two things must be in place for a tenant: CIPP must hold vulnerability data for it, and a scan group for it must already exist in NinjaOne.

{% hint style="warning" %}
CIPP does not create scan groups. You create one scan group per mapped tenant in NinjaOne, once, as described below. Tenants without a matching scan group are skipped.
{% endhint %}

{% stepper %}
{% step %}
### Check CIPP holds vulnerability data

There is nothing to schedule. CIPP collects Defender vulnerability data in its nightly data cache for every tenant licensed for Microsoft Defender for Endpoint, and the NinjaOne sync uploads that cached data. To confirm a tenant has data, or to refresh it straight away, open **Security** > **Defender** > **CVE Management**, select the tenant, make sure the page is set to **Cached**, then select **Sync**.
{% endstep %}

{% step %}
### Turn on CVE sync and set the prefix

On the NinjaOne integration page in CIPP, the same page used to enter the connection details, turn on **Enable Automated CVE Sync**, enter a **CVE Sync Scan Group Prefix** such as `CIPP-`, and select **Submit**.

For each tenant, CIPP looks for a scan group named with the prefix followed by the tenant's default domain name. With the prefix `CIPP-`, the tenant `contoso.com` needs a scan group named `CIPP-contoso.com`. The name must match exactly.
{% endstep %}

{% step %}
### Prepare a sample CSV

NinjaOne asks for a CSV when a scan group is created and takes the scan group's column names from it. Create a file with a device name column, a CVE ID column and one example row:

```
deviceName,cveId
DESKTOP-01,CVE-2024-12345
```

The same file can be reused for every scan group. Do not use the export from the **Vulnerabilities** page in CIPP: it lists each CVE once with all of its affected devices in a single column, so there is no per-device column to map.
{% endstep %}

{% step %}
### Create a scan group for each tenant in NinjaOne

In NinjaOne go to **Administration** > **Apps** > **Microsoft Defender**, open the **Scan Groups** tab and select **+ Create scan group**. Enter the name from the earlier step, upload the sample CSV, and map `deviceName` as the device identifier and `cveId` as the CVE ID. Repeat for each tenant you want to sync.

From then on CIPP reads the column names back from each scan group and uploads one row per affected device and CVE.
{% endstep %}

{% step %}
### Check the result

Run **Sync Now** for a tenant from the **Tenant Mapping** table, then check the CIPP logbook for `NinjaOneSync` entries for that tenant:

| Logbook message | Meaning |
| --- | --- |
| `CVE sync complete` | The upload was processed by NinjaOne. |
| `CVE sync skipped — scan group '...' not found` | No scan group has that exact name. Check the prefix and the tenant's default domain name. |
| `CVE sync — no vulnerability data returned` | CIPP holds no vulnerability data for the tenant. Check the tenant's Defender for Endpoint licensing and the first step. |
{% endstep %}
{% endstepper %}

{% hint style="info" %}
CVE exceptions recorded in CIPP are applied before upload, both tenant-specific exceptions and those set for all tenants, so a suppressed CVE does not reappear in NinjaOne.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
