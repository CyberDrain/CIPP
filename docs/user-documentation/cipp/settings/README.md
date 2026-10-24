---
description: View and amend the settings for your CIPP instance.
---

# Application Settings

The General tab of the application settings brings together the instance-wide controls for your CIPP deployment: version information, password generation, DNS resolution, caching, backups, retention periods, JIT admin limits and approval, and the default BEC containment actions. Each card operates independently and saves on its own, so there is no single submit action for the page.

## Version

Shows the versions currently running, with the frontend and backend reported separately, together with how this instance is hosted.

| Field           | Description                                                                                                                  |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Frontend        | The version of the CIPP web interface currently deployed.                                                                    |
| Backend         | The version of the CIPP API currently deployed.                                                                              |
| Hosting         | Whether this is a CyberDrain-hosted instance or a self-hosted one.                                                           |
| App Service SKU | The App Service plan the instance runs on, where the platform reports one.                                                   |
| Runtime Stack   | The platform the API runs on: Flex Consumption, Linux, or Windows.                                                           |
| Last Updated    | The most recent version change recorded for this instance, as the version it moved from and to, with the date and time in UTC. |

Each version displays a tick when it is current, or a warning icon together with the newer version number when an update is available. Selecting **Check For Updates** re-queries both, which is worth doing after an upgrade rather than relying on a cached result.

Selecting **Copy for Ticket** copies the whole card to your clipboard as plain text, ready to paste into a support ticket. The button reads **Copied!** for a couple of seconds to confirm.

Version changes are recorded from the next update onward, so a freshly deployed instance shows **No update recorded yet** against Last Updated until it has moved between versions at least once. The full record is on the [status.md](../advanced/container-management/status.md "mention") page.

Any detail the instance cannot report is shown as **Unknown**. The version numbers themselves fall back to Unknown when the check against the published release cannot reach GitHub, for example when the request has been rate-limited, so the rest of the card still gives you something to send with a ticket.

{% hint style="info" %}
The frontend and backend are versioned and deployed separately, so it is normal to see one flagged as out of date while the other is current during an upgrade. Both should match once the upgrade completes.
{% endhint %}

## Password Style

Shows the password generation settings currently in effect, displayed as a chip summarising the type and length.

| Type       | Description                                                                                                                                                   |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Classic    | A randomised string of letters, numbers and symbols, sized by character count. The default is 14 characters.                                                  |
| Passphrase | Several random words joined by a separator, sized by word count. The default is 4 words. Passphrases are usually easier for end users to read out and retype. |

Selecting **Configure** opens the [password-config.md](password-config.md "mention") page, where the type, length, character sets and separator are set.

{% hint style="warning" %}
If the card shows an error instead of the current setting, CIPP could not read the stored configuration. Open the configuration page and save the settings again to restore it.
{% endhint %}

## DNS Resolver

Selects which public resolver CIPP uses, with Google and Cloudflare available. The active choice is shown as the filled button.

{% hint style="info" %}
This resolver is used by the [domains-analyser](../../tenant/standards/domains-analyser/ "mention") and the [individual-domains.md](../../tools/tenant-tools/individual-domains.md "mention") only. It has no effect on any other DNS resolution CIPP performs, so changing it will not alter behaviour elsewhere in the application.
{% endhint %}

## Cache

Clears the cached data CIPP holds, including the tenant list and analyser results.

Selecting **Clear Cache** opens a confirmation dialog with one option.

| Setting                     | Description                                                                                                     |
| --------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Only Clear the Tenant Cache | Limits the operation to the tenant cache, leaving other cached data intact. Leave this off to clear everything. |

{% hint style="danger" %}
A full cache clear removes every cache table, including audit log entries that are queued but not yet processed. Those entries are lost, not reprocessed. Performance is also degraded until the caches rebuild, and personal preferences such as the selected theme are reset. Only clear the cache when support asks you to.
{% endhint %}

## Backup

Covers the system configuration backups for your CIPP instance. Selecting **Manage Backups** opens the CIPP Backup page, where backups are taken, restored, and put on an automated daily schedule.

{% hint style="info" %}
System backups exclude authentication information and extension configuration, so a restored instance still needs its SAM credentials and integration settings entered again.
{% endhint %}

## Backup Retention

Sets how long backup files are kept before automatic deletion. The value applies to both CIPP system backups and tenant backups.

| Field | Description                                                                                        |
| ----- | -------------------------------------------------------------------------------------------------- |
| Days  | The retention period in days. The minimum is 7 and the default is 30. Values below 7 are rejected. |

Enter the number of days and select **Save**. Cleanup runs daily at 2:00 AM.

## Log Retention

Sets how long CIPP log entries are kept before automatic deletion.

| Field | Description                                                                                                                        |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Days  | The retention period in days. The minimum is 7, the maximum is 365, and the default is 90. Values outside that range are rejected. |

Enter the number of days and select **Save**.

## Report Attachment Retention

Sets how long generated reports and oversized report attachments are kept.

* **Generated reports**: every Report Builder report, whether generated on demand or by a schedule, is stored with its PDF so it can be opened again later. Reports older than the retention period are deleted together with their PDFs.
* **Oversized attachments**: an attachment that would take a scheduled report email over Microsoft's 4 MB limit is uploaded to storage instead, and the email links to it. Those files, and the download links pointing at them, are kept for the retention period.

| Field | Description                                                                                                                         |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Days  | The retention period in days. The minimum is 7, the maximum is 365, and the default is 360. Values outside that range are rejected. |

Enter the number of days and select **Save**. Cleanup runs daily at 1:00 AM and deletes reports and files past the retention period. Download links to deleted files stop working.

{% hint style="info" %}
A download link expires after the retention period that applied when its email was sent. Changing the setting later does not extend links already sent.
{% endhint %}

## JIT Admin Settings

Caps how long a Just-In-Time admin account created through CIPP may remain active, which stops technicians from provisioning long-lived privileged accounts, and can require JIT Admin requests to be approved before they are carried out.

| Field                       | Description                                                                                                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Maximum Duration (ISO 8601) | The longest duration a JIT admin account may be granted. Presets range from 1 hour to 30 days, and a custom ISO 8601 duration such as `PT6H` or `P21D` can be typed directly. Leave empty for no limit. |
| Require approval for JIT Admin requests | Holds JIT Admin requests until they are approved, instead of carrying them out straight away. The fields below appear when this is on. |
| Tenants that need approval  | The tenants and tenant groups where approval applies. A request in any other tenant goes ahead as before. Tenant groups are checked when each request is made, so a tenant added to a static group later is covered too; a dynamic group picks up a newly matching tenant at its next scheduled membership refresh. If a selected group is deleted, every request needs approval until the group is removed here. Leave empty to require approval in every tenant. |
| Roles that need approval    | The Entra ID directory roles that trigger approval. A request including any of them, in a tenant that needs approval, needs approval, and a request without them goes ahead as before. Leave empty to require approval for every request, including one that only adds groups. |
| Approver roles              | The CIPP roles, built-in or custom, whose users can approve or reject requests. Required when approval is on. |
| Approvals required          | How many different approvers must approve a request before it is carried out. Defaults to 1.                    |

Select **Save Settings** to apply. The maximum duration applies to all tenants, and approval to the tenants selected above. Any attempt to create a JIT admin account exceeding the maximum duration is rejected.

{% hint style="info" %}
Custom values must be valid ISO 8601 durations, so use forms such as `PT1H`, `P1D` or `P28D`. An invalid value prevents the card from saving.
{% endhint %}

When approval is on, a request is never approved by the person who submitted it, and a single rejection ends it. Approvers are notified through the [notifications.md](notifications.md "mention") settings, and on the new CIPP infrastructure by push to any device they have registered. Requests are approved and rejected on the [Requests](../../identity/administration/jit-admin/requests.md) tab of JIT Admin, which describes the whole flow.

{% hint style="warning" %}
If the technicians who request JIT Admin access also hold an approver role, they can approve each other's requests, though never their own. Choose approver roles held by the people who should sign off on elevated access.
{% endhint %}

## BEC Remediation Defaults

Shows how many of the business email compromise containment actions are switched on by default, for example **6 of 21 actions on by default**. The defaults decide which actions start selected when a compromised user is contained, and which run when a user is contained automatically.

Selecting **Configure** opens the [bec-remediation.md](bec-remediation.md "mention") page, where each action is switched on or off.

## Other Settings Tabs

The remaining application settings are grouped on their own tabs.

| Tab                                                  | Description                                                                      |
| ---------------------------------------------------- | -------------------------------------------------------------------------------- |
| [branding.md](branding.md "mention")                 | Customises the logo and brand colour applied to generated reports and documents. |
| [permissions.md](permissions.md "mention")           | Reviews and repairs the permissions held by the CIPP service principal.          |
| [tenants.md](tenants.md "mention")                   | Manages which tenants CIPP sees, including exclusions and refresh.               |
| [backend.md](backend.md "mention")                   | Provides direct links into the underlying Azure resources for your instance.     |
| [notifications.md](notifications.md "mention")       | Configures where CIPP sends alerts, including email and webhook destinations.    |
| [partner-webhooks.md](partner-webhooks.md "mention") | Sets up partner webhooks so new tenants are onboarded automatically.             |
| [licenses.md](licenses.md "mention")                 | Manages licence exclusions used across reporting and alerting.                   |
| [features.md](features.md "mention")                 | Enables and disables optional CIPP features.                                     |
| [siem.md](siem.md "mention")                         | Configures log forwarding to an external SIEM.                                   |

{% include "../../../../.gitbook/includes/feature-request.md" %}
