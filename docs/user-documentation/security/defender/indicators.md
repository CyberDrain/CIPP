# Defender Indicators

The custom indicators in Microsoft Defender for Endpoint for the selected tenant: file hashes, certificates, IP addresses, URLs and domains that Defender allows, audits, warns about or blocks on the tenant's devices. Use it to review what each client allows or blocks, to block a known bad file or site in several tenants in one step, and to remove indicators you no longer need, without opening each client's Defender portal.

With a single tenant selected the list is read live from Defender. All Tenants and tenant groups show the data stored by CIPP, which is refreshed every night. After adding or removing indicators, select **Sync** to see the change in All Tenants.

## Action Buttons

<details>

<summary>Add Indicator</summary>

Adds up to 500 values of one type, with one action, to one or more tenants. Choose the tenants, the indicator type and the action, then enter one value per line and a title. You can also add a description, an expiry date and an alert severity.

| Type | Value | Actions |
| ------------------------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------- |
| File (SHA-256, SHA-1 or MD5 hash) | The file's hash: 64, 40 or 32 hexadecimal characters. | Allow, Audit, Warn, Block, Block and remediate |
| Certificate (SHA-1 thumbprint) | The 40 character thumbprint of the certificate that signs the files. | Allow, Block |
| IP address | A single public IPv4 address, or an IPv6 address written in full as eight groups of four digits, for example `2001:0db8:0000:0000:0000:0000:0000:0042`. Ranges, CIDR notation and private addresses are not accepted. | Allow, Audit, Warn, Block |
| URL | A full URL starting with `http://` or `https://`. | Allow, Audit, Warn, Block |
| Domain | A domain name such as `example.com`, without `http://` or a path. | Allow, Audit, Warn, Block |

* **Allow** makes Defender trust the value. See [Allow indicators](#allow-indicators) before you use it.
* **Audit** allows the value and raises an alert in Defender each time it is seen. CIPP always turns the alert on for Audit.
* **Warn** shows the user a warning that they can choose to bypass.
* **Block** blocks the file, certificate or address. For files, **Block and remediate** also quarantines the file.

CIPP checks every value before it contacts Defender and lists any value that is invalid for the chosen type. Each percent sign in a URL must be followed by two hexadecimal digits. Defender stores URLs in lowercase, so CIPP sends and compares them that way.

Before adding, CIPP reads the indicators that already exist in each tenant:

* A value that already exists with the same action is updated with the new title, description and expiry.
* A value that already exists with a different action is skipped in that tenant and left unchanged. To change its action, remove the existing indicator from this page, then add the value again with the new action.
* A value that already exists only for some device groups is skipped in that tenant and left unchanged. Change it in the Microsoft Defender portal.
* If CIPP cannot read a tenant's existing indicators, it adds nothing to that tenant and carries on with the others.

With one tenant selected, CIPP adds the indicators straight away and lists each value: added, updated, skipped or refused by Defender, with Defender's reason.

With All Tenants or two or more tenants selected, CIPP adds the indicators in the background. The confirmation shows the queue ID. Close the drawer and select the progress icon beside **Add Indicator** to see each tenant's status. A tenant shows as failed if any value was skipped, refused or unconfirmed by Defender.

Search the logbook for the queue ID and open an entry to see every value. Check the logbook before adding the same values again, because Defender may have saved a value it did not confirm. When the job finishes, select **Sync** to see the new indicators in All Tenants.

</details>

<details>

<summary>Sync</summary>

Refreshes the stored indicator data for the selected tenant, or for every tenant with All Tenants selected, and tracks the job's progress.

</details>

## Allow indicators

An Allow indicator applies to every device in each selected tenant.

* For a file, Microsoft Defender Antivirus trusts the file and does not detect or block it, even if it is malicious.
* For a certificate, Microsoft Defender Antivirus trusts every file signed with that certificate.
* For an IP address, URL or domain, devices can reach the address even where Defender would otherwise block it or show a warning. For the same address, an Allow indicator takes precedence over Block and Warn indicators.

Before CIPP adds an Allow indicator, it shows what Allow does for the chosen type and asks you to confirm that Defender will trust the values in the number of tenants selected. The confirmation clears whenever you change the tenants, the values, the type or the action.

## Table Details

| Column | Description |
| ------------------------- | ------------------------------------------------------------------------------------------- |
| Tenant | The tenant the indicator belongs to. Shown for All Tenants and tenant groups. |
| Indicator | The file hash, certificate thumbprint, IP address, URL or domain. |
| Indicator Type | FileSha256, FileSha1, FileMd5, CertificateThumbprint, IpAddress, Url or DomainName. |
| Action | Allowed, Audit, Warn, Block or BlockAndRemediate. Defender stores a certificate Block as BlockAndRemediate. |
| Title | The indicator's title. |
| Description | The indicator's description. For indicators added from CIPP it starts with the name of the technician who added them. |
| Expires | When Defender removes the indicator. Empty when it does not expire. |
| Created By | The application or account that created the indicator. Indicators added from CIPP show the CIPP application. |
| Created | When the indicator was created. |
| Device Groups | The device group names returned by Defender. Select a row to see any group IDs Defender returned. |
| Cache Timestamp | When CIPP last stored the data. Shown for stored data only. |

Selecting a row shows every field, including the severity, whether the indicator raises an alert, and who last updated it.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Remove</td><td>Removes the indicator from the tenant it belongs to. With several rows selected, CIPP removes them tenant by tenant. An indicator that is already gone counts as removed, so it is safe to try again. Defender can take a minute to show the change in its list.</td><td>true</td></tr></tbody></table>

## Filters

| Filter | Shows |
| -------- | --------------------------------- |
| Allowed | Indicators whose action is Allowed. |

## When indicators take effect

Defender sends indicators to devices in the background. A file indicator usually reaches devices in about 15 to 30 minutes. A network indicator can take up to 48 hours, and usually takes less than 2 hours.

URL indicators for HTTPS sites match the full path only in Microsoft Edge. Other browsers see only the domain of an HTTPS site, so a URL indicator with a path does not apply to them for HTTPS.

Each tenant can hold up to 15,000 indicators.

## Prerequisites

Indicators only take effect on devices that meet Microsoft's requirements. In the Microsoft Defender portal, under **Settings** > **Endpoints** > **Advanced features**:

* **Custom network indicators** must be on for IP address, URL and domain indicators.
* **Allow or block file** must be on for file indicators.

On the devices:

* IP address, URL and domain indicators need network protection in block mode.
* File indicators need cloud-delivered protection and file hash computation turned on.

Microsoft documents the full requirements for [file indicators](https://learn.microsoft.com/en-us/defender-endpoint/indicator-file), [certificate indicators](https://learn.microsoft.com/en-us/defender-endpoint/indicator-certificates) and [IP address, URL and domain indicators](https://learn.microsoft.com/en-us/defender-endpoint/indicator-ip-domain).

## Data and permissions

CIPP reads and writes indicators with the application permission `Ti.ReadWrite.All` on the Windows Defender ATP API. It is added to the CIPP application when the tenant's permissions are updated, so a tenant may need its permissions refreshed before the first read or change succeeds.

Defender records indicators added from CIPP against the CIPP application, so the Microsoft Defender portal shows the CIPP application as the creator. CIPP puts your name at the start of the description, for example `you@example.com via CIPP: Ticket 4411`, and the CIPP logbook records who added or removed indicators, the tenant, the action and Defender's indicator IDs.

Viewing indicators needs the `Security.Defender.Read` CIPP permission. Adding and removing them needs `Security.Defender.ReadWrite`. Following the progress of an add to several tenants needs `CIPP.Core.Read`, and reading the results in the logbook needs `CIPP.Logs.Read`. The built-in editor, admin and superadmin roles include `Security.Defender.ReadWrite`, so their users can add and remove indicators, including Allow indicators, in every tenant they have access to. A custom role needs `Security.Defender.ReadWrite` added before its users can make changes.

{% include "../../../../.gitbook/includes/feature-request.md" %}
