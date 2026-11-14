# Non-Compliant Devices

Shows which compliance settings are making devices non-compliant, the same data as the noncompliant devices and settings report in the Microsoft Intune admin center. Failing settings are grouped per policy and ranked by how many devices they affect, so the settings worth fixing first are at the top, and each one opens to the devices failing it.

{% hint style="info" %}
This page always reads cached data. Each sync asks Intune to prepare the report, which takes a few minutes, and the following sync reads it. If nothing has been collected yet, or every device is compliant, the page says that no failing compliance settings are cached for the tenant.
{% endhint %}

## Top Failing Settings

A bar chart of the ten failing settings that affect the most devices, with one bar per setting and its device count. Where the same setting fails under more than one policy, the bar label names the policy as well. The total shows the number of distinct non-compliant devices, so a device failing several settings is counted once.

Selecting a bar filters the **Failing Compliance Settings** table to that setting. A **Filtered** chip appears above the charts while a filter is applied, and removing the chip clears it.

## Non-Compliant Devices by OS

A donut chart of the non-compliant devices broken down by operating system. Selecting a segment filters the **Failing Compliance Settings** table to devices running that operating system, the same way as the bar chart.

## Failing Compliance Settings

One row per failing setting in each policy.

| Column          | Description                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Setting Name    | The compliance setting the devices are failing.                                                                                |
| Policy Name     | The compliance policy the setting belongs to.                                                                                  |
| Built In Policy | Whether the setting belongs to Intune's built-in Default Device Compliance Policy rather than a compliance policy of your own. |
| Devices         | The number of devices failing the setting.                                                                                     |
| Error Count     | How many of the failing devices report the setting with an error status.                                                       |

{% hint style="info" %}
Settings under the built-in Default Device Compliance Policy fail for reasons such as a device having no compliance policy assigned, rather than a setting you configured. Fixing them means assigning a compliance policy or dealing with the device itself.
{% endhint %}

## Failing Devices

Selecting a row in **Failing Compliance Settings** opens a flyout listing the devices failing that setting.

| Column              | Description                                                                                                                         |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Device Name         | The name of the device.                                                                                                             |
| Setting Status      | The state Intune reports for the setting on the device.                                                                             |
| Error Code          | The Intune error code for the failure, shown in hexadecimal with the original number in brackets, ready to search for.              |
| User Principal Name | The user the setting was evaluated for.                                                                                             |
| Compliance State    | The device's current overall compliance state, which tells a device still in its grace period apart from one that is non-compliant. |
| Os                  | The device's operating system.                                                                                                      |
| Os Version          | The device's operating system version.                                                                                              |

Each device row offers the following actions.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Device</td><td>Opens the device's <a data-mention href="devices/device/README.md">View Device</a> page in CIPP.</td><td>false</td></tr><tr><td>Sync Device</td><td>Opens the sync status drawer for the device, where <strong>Sync now</strong> asks the device to check in with Intune and the drawer follows the sync's progress. See <a data-mention href="devices/README.md">Devices</a> for the drawer.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
