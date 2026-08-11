---
description: View and amend the settings for your CIPP instance.
---

# Application Settings

The General tab of the application settings brings together the instance-wide controls for your CIPP deployment: version information, password generation, DNS resolution, caching, backups, retention periods, and JIT admin limits. Each card operates independently and saves on its own, so there is no single submit action for the page.

## Version

Shows the versions currently running, with the frontend and backend reported separately.

| Field    | Description                                               |
| -------- | --------------------------------------------------------- |
| Frontend | The version of the CIPP web interface currently deployed. |
| Backend  | The version of the CIPP API currently deployed.           |

Each version displays a tick when it is current, or a warning icon together with the newer version number when an update is available. Selecting **Check For Updates** re-queries both, which is worth doing after an upgrade rather than relying on a cached result.

{% hint style="info" %}
The frontend and backend are versioned and deployed separately, so it is normal to see one flagged as out of date while the other is current during an upgrade. Both should match once the upgrade completes.
{% endhint %}

## Password Style

Shows the password generation settings currently in effect, displayed as a chip summarizing the type and length.

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
This resolver is used by the [domains-analyzer](../../tenant/standards/domains-analyzer/ "mention") and the [individual-domains.md](../../tools/tenant-tools/individual-domains.md "mention") only. It has no effect on any other DNS resolution CIPP performs, so changing it will not alter behavior elsewhere in the application.
{% endhint %}

## Cache

Clears the cached data CIPP holds, including the tenant list and analyzer results.

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

## JIT Admin Settings

Caps how long a Just-In-Time admin account created through CIPP may remain active, which stops technicians from provisioning long-lived privileged accounts.

| Field                       | Description                                                                                                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Maximum Duration (ISO 8601) | The longest duration a JIT admin account may be granted. Presets range from 1 hour to 30 days, and a custom ISO 8601 duration such as `PT6H` or `P21D` can be typed directly. Leave empty for no limit. |

Select **Save Settings** to apply. The limit applies globally across all tenants, and any attempt to create a JIT admin account exceeding it is rejected.

{% hint style="info" %}
Custom values must be valid ISO 8601 durations, so use forms such as `PT1H`, `P1D` or `P28D`. An invalid value prevents the card from saving.
{% endhint %}

## Other Settings Tabs

The remaining application settings are grouped on their own tabs.

| Tab                                                  | Description                                                                      |
| ---------------------------------------------------- | -------------------------------------------------------------------------------- |
| [branding.md](branding.md "mention")                 | Customizes the logo and brand color applied to generated reports and documents. |
| [permissions.md](permissions.md "mention")           | Reviews and repairs the permissions held by the CIPP service principal.          |
| [tenants.md](tenants.md "mention")                   | Manages which tenants CIPP sees, including exclusions and refresh.               |
| [backend.md](backend.md "mention")                   | Provides direct links into the underlying Azure resources for your instance.     |
| [notifications.md](notifications.md "mention")       | Configures where CIPP sends alerts, including email and webhook destinations.    |
| [partner-webhooks.md](partner-webhooks.md "mention") | Sets up partner webhooks so new tenants are onboarded automatically.             |
| [licenses.md](licenses.md "mention")                 | Manages license exclusions used across reporting and alerting.                   |
| [features.md](features.md "mention")                 | Enables and disables optional CIPP features.                                     |
| [siem.md](siem.md "mention")                         | Configures log forwarding to an external SIEM.                                   |

{% include "../../../../.gitbook/includes/feature-request.md" %}
