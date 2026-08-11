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
| Hudu API Key                                                                    | The API key generated in Hudu. Stored securely and masked once saved.                                                                                                                             |
| Create missing users in Hudu                                                    | Creates an asset for any Microsoft 365 user without a matching record in the mapped user layout. Without this, CIPP only updates users that already exist in Hudu.                                |
| Create missing devices in Hudu                                                  | Creates an asset for any Intune device without a matching record in the mapped device layout.                                                                                                     |
| Exclude device serials (comma separated)                                        | Additional serial numbers to skip when matching and creating devices. A set of common placeholder serials is always excluded regardless of this setting.                                          |
| Import domains from M365                                                        | Creates a Hudu website record for each domain in the tenant that does not already exist.                                                                                                          |
| Monitor domains in Hudu                                                         | Enables DNS, SSL and WHOIS monitoring on the website records created by the previous setting. Without it, records are created paused with monitoring disabled.                                    |
| Hide Empty Roles in Magic Dash                                                  | Omits directory roles with no members from the assigned roles table, which keeps the Magic Dash considerably shorter.                                                                             |
| Include link to Partner Center Service management page (partner.microsoft.com)  | Adds a Partner Center link to the tenant's portal links.                                                                                                                                          |
| Include link to Defender Portal (security.microsoft.com)                        | Adds a Defender portal link to the tenant's portal links.                                                                                                                                         |
| Include link to Compliance Portal (compliance.microsoft.com)                    | Adds a Purview compliance portal link to the tenant's portal links.                                                                                                                               |
| Connect to HUDU through CloudFlare Tunnel with the Service Account credentials. | Sends the Cloudflare Access service token with every request to Hudu. Only appears when the Cloudflare integration is enabled.                                                                    |
| Reschedule next sync date                                                       | Sets a future date to delay the next scheduled synchronisation, which is useful for keeping the first run outside business hours. Leave blank to sync at the next scheduled time.                 |

{% hint style="info" %}
The Microsoft 365 and Entra portal links are always included. The Partner Center, Defender and Compliance links are optional because not every technician has access to them.
{% endhint %}

## Obtaining an API Key in Hudu

{% stepper %}
{% step %}
### Create the key

Sign in to Hudu as an Administrator, go to **Admin** > **Account Administration** > **API Keys**, and select **+ New API Key**.
{% endstep %}

{% step %}
### Configure the key

Give it a name such as _CIPP Integration_, set **Limit scope to** to _Full Access_, and leave **Company** blank. None of the options under **Key can perform the following actions** are required.

Optionally restrict **Allowed IP Addresses** to your function app's outbound addresses. CyberDrain-hosted clients can find these at [management.cipp.app](https://management.cipp.app/).
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

Select **Submit**, then select **Test**. A message confirming the connection and reporting your Hudu version means the URL and API key are correct.
{% endstep %}

{% step %}
### Map companies and layouts

Work through the **Tenant Mapping** and **Field Mapping** tabs described below. Scheduled synchronisation is only set up once tenants are mapped.
{% endstep %}
{% endstepper %}

## Organization Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a Hudu company. Only mapped tenants are synchronised, and mapping a tenant is what causes CIPP to schedule its daily synchronisation.

To map manually, choose a tenant, choose the matching entry under **Select Hudu Company**, and select the add button. **Automap Companies** fills in matches automatically, and the refresh button reloads the company list from Hudu. Mappings are only written when you select **Submit**.

| Column          | Description                                           |
| --------------- | ----------------------------------------------------- |
| IntegrationName | The name of the Hudu company the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant.  |
| TenantDomain    | The default domain name of the mapped tenant.         |
| TenantId        | The tenant's Microsoft customer ID.                   |

Individual mappings can be removed with the **Delete Mapping** row action.

{% hint style="info" %}
Automapping compares the tenant's display name with the Hudu company name, ignoring case, punctuation and trailing legal suffixes such as Ltd, Limited, LLC, Inc, GmbH or BV. Where more than one company normalises to the same name the match is ambiguous and is left for you to map manually. Review the proposed matches before saving.
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

Once a tenant is mapped, CIPP schedules a daily synchronisation for it. Each run publishes a Magic Dash card on the Hudu company titled **Microsoft 365 -&#x20;**_**tenant name**_, showing the licensed user count and containing tenant detail, portal links and the assigned roles table. User and device assets are then created or updated in the mapped layouts, and domains are imported as website records where enabled.

Use **Reschedule next sync date** to push the next run to a specific date, which is the cleanest way to keep the initial full synchronisation out of business hours.

{% hint style="warning" %}
**Force Sync** on this page reschedules the synchronisation tasks rather than running them immediately. The message confirms that tasks will start within fifteen minutes.
{% endhint %}

The Integration Sync page shows per-tenant synchronisation status and is the first place to look when a tenant's data appears stale.

## Custom CSS

The Microsoft 365 rich text field can render with cut-off tables or cramped formatting depending on your Hudu theme. Adding the following custom CSS in your Hudu settings improves the layout of the tables, license tiles and link buttons CIPP generates.

```css
.card__item table {
  border-collapse: collapse;
  margin: 5px 0;
  font-size: 0.8em;
  font-family: sans-serif;
  min-width: 400px;
  box-shadow: 0 0 20px rgba(0, 0, 0, 0.15);
}
.card__item h2,
.card__item p {
  font-size: 0.8em;
  font-family: sans-serif;
}
.card__item th,
.card__item td {
  padding: 5px 5px;
  width: auto;
}
.card__item thead tr {
  text-align: left;
}
.card__item tr {
  border-bottom: 1px solid #dddddd;
}

.custom-fast-fact.custom-fast-fact--warning { background: #f5c086; }
.custom-fast-fact.custom-fast-fact--datto-low { background: #2c81c8; }
.custom-fast-fact.custom-fast-fact--datto-moderate { background: #f7c210; }
.custom-fast-fact.custom-fast-fact--datto-high { background: #f68218; }
.custom-fast-fact.custom-fast-fact--datto-critical { background: #ec422e; }

.nasa__block {
  height: auto;
}
.nasa__block td {
  white-space: normal;
  word-wrap: break-word;
  word-break: break-word;
}

.mce-content-body {
  max-height: none !important;
  overflow: visible !important;
}
.writer-wrap {
  max-height: none;
  overflow-y: auto;
}

/* === License & Management Link Card Grids === */

/* Suppress generated <br> tags between sections */
.rich_text_content .o365 + br {
  display: none;
}

/* Flex for management button rows */
.o365 {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 8px 0;
  align-items: stretch;
}

/* Grid for license tile rows — equal-width columns */
.o365:has(.o365__app) {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(155px, 1fr));
}

.o365__app {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 10px 14px;
  min-width: 130px;
  border-radius: 6px;
  border: 1px solid rgba(200, 200, 200, 0.15);
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
  font-family: sans-serif;
  font-size: 0.8em;
  text-align: center;
}
.o365__app strong {
  font-size: 1em;
  line-height: 1.2;
  display: block;
}
.o365__app font {
  font-size: 0.72rem !important;
  opacity: 0.65;
  display: block;
  line-height: 1.2;
}

.o365 .button {
  border-radius: 6px;
  padding: 8px 14px;
  font-size: 0.85em;
  font-family: sans-serif;
  font-weight: 500;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
  transition: box-shadow 0.15s ease, transform 0.1s ease;
  white-space: nowrap;
  margin: 0;
  cursor: pointer;
}
.o365 .button:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35);
  transform: translateY(-1px);
}
.o365 .button a {
  display: flex;
  align-items: center;
  gap: 6px;
  text-decoration: none;
}

.section-label {
  font-family: sans-serif;
  font-size: 0.7em;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--primaryl1);
  margin-top: 16px;
  margin-bottom: 6px;
  padding-bottom: 5px;
  padding-left: 2px;
  border-bottom: 1px solid rgba(21, 112, 239, 0.3);
}
```

## Special Thanks

Special thanks to Luke Whitelock and his [HuduM365Automation](https://github.com/lwhitelock/HuduM365Automation) function app code.

{% include "../../../../.gitbook/includes/feature-request.md" %}
