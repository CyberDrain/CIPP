# Defender Devices

Every device that Microsoft Defender for Endpoint knows about in the selected tenant, including devices onboarded directly to Defender without Intune. Use it to find devices that have stopped reporting, devices where the antivirus is passive or its signatures are out of date, and devices that can be onboarded but are not, without opening each client's Defender portal.

The page always shows data stored by CIPP, so it is quick across All Tenants and tenant groups.

## Action Buttons

<details>

<summary>Sync</summary>

Refreshes the device data for the selected tenant and tracks the job's progress. Sync is not available for All Tenants or tenant groups. The data is also refreshed every night.

</details>

## Table Details

| Column | Description |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| Tenant | The tenant the device belongs to. Shown for All Tenants and tenant groups. |
| Device Name | The device's DNS name. |
| Os Platform | The operating system, for example Windows11. |
| Version | The operating system version, for example 26H2. |
| Health Status | The sensor's state in Defender, for example Active, Inactive or ImpairedCommunication. |
| Onboarding Status | Whether the device is onboarded, can be onboarded, is unsupported or has insufficient information. |
| Risk Score | The device's risk score in Defender. |
| Exposure Level | The device's exposure level in Defender. |
| Antivirus Mode | Whether Microsoft Defender Antivirus is Active, Passive, Disabled, Other, EDR Blocked or Passive Audit. |
| Signatures Up To Date | True, False or Unknown, as reported by Defender. |
| Signatures Updated | When the antivirus signatures were last updated on the device. |
| Last Seen | When Defender last received a full report from the device. |
| Machine Tags | The tags set on the device in Defender. |
| Cache Timestamp | When CIPP last stored this device's data. |

Selecting a row shows every stored field, including the antivirus engine and platform status, the last scan results, the last known IP addresses and whether Intune manages the device.

Devices appear for as long as Defender keeps them, which is limited by the retention period configured in the tenant.

## Filters

| Filter | Shows |
| ----------------------- | -------------------------------------------------------- |
| Inactive | Devices whose sensor health is Inactive. |
| Antivirus passive | Devices where Microsoft Defender Antivirus is passive. |
| Signatures out of date | Devices where the antivirus signatures are not current. |
| Can be onboarded | Devices Defender has found that are not yet onboarded. |

## Data and permissions

CIPP reads this data with the application permission Read all machine profiles on the Windows Defender ATP API. The permission is added to the CIPP application when the tenant's permissions are updated, so a tenant may need its permissions refreshed before the first sync succeeds.

Antivirus health reporting requires Defender for Business or Defender for Endpoint Plan 2. Antivirus columns stay empty until Defender reports health data for the device, which can take some time after onboarding. Check Cache Timestamp to see when CIPP last stored the device data.

{% include "../../../../.gitbook/includes/feature-request.md" %}
