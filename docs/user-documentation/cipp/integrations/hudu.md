# Hudu

The Hudu integration writes Microsoft 365 tenant, user, device and domain information from CIPP into Hudu. Tenant-level information is published as a Magic Dash card on the Hudu company, while user and device detail is written into a rich text field on the asset layouts you nominate. You control which parts are populated, so it is reasonable to sync only what you need.

{% hint style="danger" %}
If Hudu sits behind a Cloudflare Zero Trust tunnel, set up the [cloudflare.md](cloudflare.md "mention") integration as well and enable **Connect to HUDU through CloudFlare Tunnel with the Service Account credentials.** That toggle only appears on this page once the Cloudflare integration is enabled.
{% endhint %}

{% hint style="info" %}
User and device information is written to a rich text field named **Microsoft 365**. CIPP adds this field to the asset layouts you map, so it appears after the first synchronisation rather than needing to be created by hand. The layout mapped for users also gains an **Email Address** text field, positioned first and shown in list views.
{% endhint %}

## Settings

| Setting                                                                         | Description                                                                                                                                                                                       |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                                              | Turns the integration on. Every other setting, the **Test** and **Force Sync** buttons, and the **Tenant Mapping** and **Field Mapping** tabs remain unavailable until this is enabled and saved. |
| Please enter your Hudu URL                                                      | The full URL of your Hudu instance, such as `https://yourcompany.huducloud.com`, or your self-hosted address.                                                                                     |
| Hudu API Key                                                                    | The API key generated in Hudu. Stored securely and masked once saved. Enable **Password Access** on the key when synchronising LAPS passwords or BitLocker recovery keys.                         |
| Create missing users in Hudu                                                    | Creates an asset for any Microsoft 365 user without a matching record in the mapped user layout. Without this, CIPP only updates users that already exist in Hudu.                                |
| Create missing devices in Hudu                                                  | Creates an asset for any Intune device without a matching record in the mapped device layout.                                                                                                     |
| Sync Windows LAPS passwords to Hudu                                             | Adds the LAPS account, password and backup date to matching Windows device assets in the mapped device layout. Individual tenants can be excluded on the **Tenant Mapping** tab.                                                                                    |
| Sync BitLocker recovery keys to Hudu                                             | Adds paired key ID and recovery-key fields for each BitLocker OS, fixed data, removable data or unknown drive to matching Windows device assets. Individual tenants can be excluded on the **Tenant Mapping** tab.                                                  |
| Exclude device serials (comma separated)                                        | Additional serial numbers to skip when matching and creating devices. A set of common placeholder serials is always excluded regardless of this setting.                                          |
| Import domains from M365                                                        | Creates a Hudu website record for each domain in the tenant that does not already exist.                                                                                                          |
| Monitor domains in Hudu                                                         | Enables DNS, SSL and WHOIS monitoring on the website records created by the previous setting. Without it, records are created paused with monitoring disabled.                                    |
| Hide Empty Roles in Magic Dash                                                  | Omits directory roles with no active or eligible members from the Magic Dash roles list, which keeps it considerably shorter.                                                                                       |
| Date and number format                                                          | The locale used for dates and numbers in the Magic Dash and the **Microsoft 365** field. Defaults to English (United Kingdom). Dates and times are shown in the CIPP time zone.                                   |
| Include link to Partner Center Service management page (partner.microsoft.com)  | Adds a Partner Center link to the tenant's portal links.                                                                                                                                          |
| Include link to Defender Portal (security.microsoft.com)                        | Adds a Defender portal link to the tenant's portal links.                                                                                                                                         |
| Include link to Compliance Portal (compliance.microsoft.com)                    | Adds a Purview compliance portal link to the tenant's portal links.                                                                                                                               |
| Connect to HUDU through CloudFlare Tunnel with the Service Account credentials. | Sends the Cloudflare Access service token with every request to Hudu. Only appears when the Cloudflare integration is enabled.                                                                    |
| Reschedule next sync date                                                       | Sets a future date to delay the next scheduled synchronisation, which is useful for keeping the first run outside business hours. Leave blank to sync at the next scheduled time.                 |

{% hint style="info" %}
The M365 Admin Portal, Exchange Admin Portal, Entra Portal, Intune, Teams Portal, SharePoint Portal, and Azure Portal links are always included. The Partner Center, Defender, and Compliance links are optional because not every technician has access to them.
{% endhint %}

## Obtaining an API Key in Hudu

{% stepper %}
{% step %}
### Create the key

Sign in to Hudu as an Administrator, go to **Admin** > **Account Administration** > **API Keys**, and select **+ New API Key**.
{% endstep %}

{% step %}
### Configure the key

Give it a name such as _CIPP Integration_, set **Limit scope to** to _Full Access_, and leave **Company** blank. Enable **Password Access** under **Key can perform the following actions** when synchronising LAPS passwords or BitLocker recovery keys. The other actions are not required, apart from the delete action described below.

{% hint style="info" %}
Enable the **Delete** action if you want CIPP to remove old Magic Dashes. When a tenant is renamed, its Magic Dash title changes and the dash under the old name is left behind. With the delete action, the next synchronisation removes it. Without it, CIPP logs a warning naming the old dashes. Magic Dashes can only be removed through the Hudu API, and a key's actions cannot be changed after it is created. To clean up later, either create a new key with the delete action and enter it in CIPP, or remove the dashes yourself with the [HuduAPI](https://www.powershellgallery.com/packages/HuduAPI) PowerShell module and a key that has the delete action:

```powershell
Install-Module HuduAPI
New-HuduBaseURL 'https://yourcompany.huducloud.com'
New-HuduAPIKey '<key with the delete action>'
Get-HuduMagicDashes -Title 'Microsoft 365 - Old Tenant Name' | Remove-HuduMagicDash
```
{% endhint %}

Optionally restrict **Allowed IP Addresses** to your function app's outbound addresses. CyberDrain-hosted clients can find these at [management.cipp.app](https://management.cipp.app/).

{% hint style="warning" %}
Hudu's global **IP Access Control** list (**Admin** > **Security**) applies to API keys as well. If it is enabled, add CIPP's outbound addresses there too, even when the key itself allows all IPs, or requests fail with `Unauthorized IP Address`. These addresses can change, so update the list if the integration stops working.
{% endhint %}
{% endstep %}

{% step %}
### Store the key

Select **Create New Key** and copy the key somewhere secure. It is not retrievable afterwards.
{% endstep %}
{% endstepper %}

## Configuring the Integration in CIPP

{% stepper %}
{% step %}
### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
### Enter the connection details

Enter your Hudu URL and the **Hudu API Key** you created.
{% endstep %}

{% step %}
### Choose what to synchronise

Work through the remaining toggles to decide whether missing users and devices are created, whether domains are imported and monitored, and which portal links appear. Add any device serials you want ignored.
{% endstep %}

{% step %}
### Save and test

Select **Submit**, then select **Test**. A message confirming the connection and reporting your Hudu version means the URL and API key are correct. If the test fails, the message includes the error returned by Hudu.
{% endstep %}

{% step %}
### Map companies and layouts

Work through the **Tenant Mapping** and **Field Mapping** tabs described below. Scheduled synchronisation is only set up once tenants are mapped.
{% endstep %}
{% endstepper %}

## Organisation Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a Hudu company. Only mapped tenants are synchronised, and mapping a tenant is what causes CIPP to schedule its daily synchronisation.

{% hint style="warning" %}
Saving on the **Tenant Mapping** and **Field Mapping** tabs requires a role with unrestricted tenant access, meaning **Allowed Tenants** left as `AllTenants` with nothing in **Blocked Tenants**. A role scoped to particular tenants or tenant groups can read the existing mappings but is refused when it selects **Submit** or **Automap Companies**. See [roles.md](../../../setup/setting-up-cipp/roles.md "mention").
{% endhint %}

To map manually, choose a tenant, choose the matching entry under **Select Hudu Company**, and select the add button. **Automap Companies** fills in matches automatically, and the refresh button reloads the company list from Hudu. Manual mappings are only written when you select **Submit**.

| Column          | Description                                           |
| --------------- | ----------------------------------------------------- |
| IntegrationName | The name of the Hudu company the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant.  |
| SyncPasswords   | Whether LAPS passwords and BitLocker recovery keys are synchronised for this tenant. Shown as true by default, including for mappings created before the column existed. |
| TenantDomain    | The default domain name of the mapped tenant.         |
| TenantId        | The tenant's Microsoft customer ID.                   |

Each row also offers these actions:

| Action | Description |
| --- | --- |
| Sync Now | Queues an on-demand synchronisation for that tenant only, without waiting for the next scheduled run. |
| Exclude password data (LAPS/BitLocker) | Stops LAPS and BitLocker data being synchronised for this tenant. Greyed out once **SyncPasswords** is false. |
| Include password data | Resumes LAPS and BitLocker synchronisation for this tenant. Greyed out while **SyncPasswords** is true. |
| Delete Mapping | Removes the mapping. |

The exclude and include actions change the table only, so select **Submit** to save the change. The **Sync Windows LAPS passwords** and **Sync BitLocker recovery keys** settings must still be on for password data to be synchronised at all. On the next synchronisation of an excluded tenant, CIPP clears any LAPS and BitLocker values previously written to that tenant's device assets in Hudu.

{% hint style="info" %}
Automapping first follows the HaloPSA integration: when a tenant is mapped to a Halo client in CIPP and a Hudu company is synced from that same Halo client, the tenant is mapped to that company. A tenant with no Halo match falls back to a Hudu company whose name exactly matches the tenant's display name. Archived companies are ignored, existing mappings are never overwritten, and these mappings are saved immediately and scheduled for synchronisation.

**Automap Companies** also suggests looser name matches that ignore case, punctuation and trailing legal suffixes such as Ltd, Limited, LLC, Inc, GmbH or BV. Those appear in the table but are only saved when you select **Submit**, so review them first. Where more than one company matches, the tenant is skipped and left for you to map manually.
{% endhint %}

{% hint style="info" %}
While the integration is enabled, CIPP also runs the HaloPSA and exact name matching automatically every two hours, so newly added tenants are mapped and synchronised without visiting this page. It runs straight after the HaloPSA automapping, so a tenant newly mapped to a Halo client can be carried through to its Hudu company in the same run. Each mapping it creates is written to the Logbook. The looser name suggestions are only made by **Automap Companies**.
{% endhint %}

{% hint style="warning" %}
Archived Hudu companies are skipped during synchronisation, and this is recorded in the sync log rather than raised as an error. If a mapped tenant never seems to update, check whether its Hudu company has been archived.
{% endhint %}

## Field Mapping

The **Field Mapping** tab nominates which Hudu asset layouts receive Microsoft 365 user and device data.

| Field                         | Description                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Asset Layout for M365 Users   | The layout used for user assets. The built-in People layout is recommended, as using a layout with an unexpected structure tends to cause matching problems. |
| Asset Layout for M365 Devices | The layout used for device assets.                                                                                                                           |

Leave either set to `--- Do not synchronize ---` to skip that data type entirely. Select **Submit** to save, and use the refresh button after creating new layouts in Hudu.

{% hint style="info" %}
CIPP adds the fields it needs to whichever layouts you map, so no preparation is required in Hudu beyond having the layouts exist. Leaving a layout unmapped disables creation of that asset type as well, regardless of the **Create missing users** and **Create missing devices** settings.
{% endhint %}

## What Gets Synchronised

Once a tenant is mapped, CIPP schedules a daily synchronisation for it. User and device assets are created or updated in the mapped layouts, domains are imported as website records where enabled, and a Magic Dash card is published on the Hudu company.

### Magic Dash

The card is titled **Microsoft 365 -&#x20;**_**tenant name**_. Its tile shows the licensed user count and, when something needs attention, how many items need it, and turns red. Opening it shows:

* the tenant name, default domain, tenant ID and portal links, followed by a **Needs attention** strip for licenses that are fully or at least 90% assigned and for five or more Global Administrators
* tiles for licensed users, license SKUs, Global Administrators and verified domains
* basic tenant information and the role holders, listed by number of directory roles with Global Administrators first and service principals marked with a robot icon
* license usage, with purchased but unassigned licenses grouped below
* a collapsible list of every directory role and its members. For tenants using Privileged Identity Management, eligible members are shown with their eligibility end date and expired eligibilities are left out. **Hide Empty Roles in Magic Dash** still applies.
* the licensed users with their licenses, devices and Entra and Microsoft 365 admin links, with resource accounts such as rooms and queues grouped separately

When a tenant is renamed, the next synchronisation removes the dash left under the old title, provided the API key has the delete action. Only dashes that carry the tenant's ID are removed, so dashes for other tenants mapped to the same company are left alone.

### User assets

The **Microsoft 365** field on each user asset opens with a header showing the user's name, account status, job title and links to Entra, Teams, Intune and CIPP. A **Needs attention** strip follows when the mailbox or OneDrive is at least 90% full, a device is non-compliant or has not synced in over 30 days, a Conditional Access policy is report-only, mail is being forwarded, or the account is disabled. Below it are cards for contact details, mailbox and OneDrive usage, mailbox access and settings, licenses and aliases, Conditional Access, Intune devices, groups and service plans. Cards with nothing to show are left out. The asset is only rewritten when this content changes.

### Device assets

The **Microsoft 365** field on each device asset opens with a header showing the device name, compliance state, operating system and version, primary user and links to Intune and, where the Hudu asset has Datto RMM or ConnectWise cards, to Datto RMM, Datto RMM Remote, CW Automate and CW Control. A **Needs attention** strip follows when the device is non-compliant, has not synced in over 30 days, or its storage is at least 90% full. Below it are cards for device details, hardware with a storage usage bar, enrollment and security (including Device Guard, virtualization-based security and Credential Guard), compliance policies and groups. As with users, the asset is only rewritten when this content changes.

Each tenant's synchronisation first checks that CIPP can reach Hudu with the saved API key. If it cannot, that tenant's run stops straight away and the Hudu error is recorded in the logbook. Select **Test** to confirm the connection.

Use **Reschedule next sync date** to push the next run to a specific date, which is the cleanest way to keep the initial full synchronisation out of business hours.

{% hint style="warning" %}
**Force Sync** on this page reschedules the synchronisation tasks rather than running them immediately. The message confirms that tasks will start within fifteen minutes.
{% endhint %}

The Integration Sync page shows per-tenant synchronisation status and is the first place to look when a tenant's data appears stale.

## Custom CSS

No custom CSS is needed. Everything CIPP writes to Hudu carries its own styling and works in Hudu's light and dark themes.

{% hint style="warning" %}
If you added custom CSS from an earlier version of this page, remove it. Those rules targeted every table in an asset field, so they also restyle the current layouts.
{% endhint %}

## Special Thanks

Special thanks to Luke Whitelock and his [HuduM365Automation](https://github.com/lwhitelock/HuduM365Automation) function app code.

{% include "../../../../.gitbook/includes/feature-request.md" %}
