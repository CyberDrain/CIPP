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

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Isolate device</td><td>Cuts the device off the network through Microsoft Defender for Endpoint. <strong>Full</strong> blocks all network traffic except the device's connection to Defender. <strong>Selective</strong> allows the limited connections Microsoft permits during selective isolation; check Microsoft's documentation for the apps and operating systems it supports. Use Release from isolation to reconnect the device when it is safe. Shown for onboarded devices only.</td><td>false</td></tr><tr><td>Release from isolation</td><td>Restores the device's network access. Shown for every device, so a device whose onboarding status is out of date can still be released.</td><td>false</td></tr><tr><td>Run antivirus scan</td><td>Starts a <strong>Quick</strong> or <strong>Full</strong> Microsoft Defender Antivirus scan on the device. Defender may refuse a new scan while another is still running. Shown for onboarded devices only.</td><td>false</td></tr><tr><td>Action history</td><td>Opens the device's isolation, release and antivirus scan history. See <a href="#action-history">Action history</a>.</td><td>false</td></tr></tbody></table>

Each action asks for confirmation, names the device and its tenant, and accepts an optional comment such as a ticket number. Actions are sent one device at a time. With All Tenants or a tenant group selected, the action goes to the tenant the device belongs to.

The device must reach Defender to apply an isolation or a remote release. A full-tunnel VPN or a web proxy can prevent an isolated device from reaching Defender. If a remote release fails, see Microsoft's [isolation and recovery guidance](https://learn.microsoft.com/en-us/defender-endpoint/respond-machine-alerts#isolate-devices-from-the-network), including the force-release option for supported Windows devices.

Defender records these actions against the CIPP application, so the Microsoft Defender portal shows the CIPP application as the requestor. CIPP puts your name at the start of the action comment, for example `you@example.com via CIPP: Ticket 4411`, and the CIPP logbook records who sent the action, the tenant, the device and Defender's action ID.

## Action History

Shows up to 50 of the device's most recent isolation, release and antivirus scan actions, newest first. For an antivirus scan, Succeeded means the device has started the scan; the scan itself can take several minutes, or much longer for a Full scan, and a scan sent while another is still running fails. CIPP reads the history from Defender each time the window opens; select **Refresh** to see the latest request status.

| Column | Description |
| ------------ | ------------------------------------------------------------------------------------------------ |
| Action | Isolate, Release from isolation or Antivirus scan, with the isolation or scan type where Defender reports it. |
| Status | Defender's status for the action, for example Pending, InProgress, Succeeded or Failed, with Defender's error code when it failed. |
| Requested | When the action was sent. |
| Last updated | When Defender last updated the action's status. |
| Requested by | The application or account Defender recorded as the requestor. Actions sent from CIPP show the CIPP application. |
| Comment | The action comment, which starts with the name of the technician who sent it from CIPP. |

While an action of the same kind is still in progress on a device, Defender refuses a new one or returns the action already in progress, so the action ID CIPP shows can belong to the earlier action. If sending an action returns an error, or you are not sure whether Defender received it, check the action history, or the Action center in the Microsoft Defender portal, before sending it again.

## Filters

| Filter | Shows |
| ----------------------- | -------------------------------------------------------- |
| Inactive | Devices whose sensor health is Inactive. |
| Antivirus passive | Devices where Microsoft Defender Antivirus is passive. |
| Signatures out of date | Devices where the antivirus signatures are not current. |
| Can be onboarded | Devices Defender has found that are not yet onboarded. |

## Data and permissions

CIPP reads this data and the action history with the application permission Read all machine profiles on the Windows Defender ATP API. Isolating and releasing a device use the application permission Isolate machine, and antivirus scans use Scan machine. These permissions are added to the CIPP application when the tenant's permissions are updated, so a tenant may need its permissions refreshed before the first sync or action succeeds.

Sending an action needs the `Security.Defender.ReadWrite` CIPP permission, and viewing the action history needs `Security.Defender.Read`. The built-in editor, admin and superadmin roles include `Security.Defender.ReadWrite`, so their users can isolate, release and scan devices in every tenant they have access to. A custom role needs `Security.Defender.ReadWrite` added before its users can send actions.

Antivirus health reporting requires Defender for Business or Defender for Endpoint Plan 2. Antivirus columns stay empty until Defender reports health data for the device, which can take some time after onboarding. Check Cache Timestamp to see when CIPP last stored the device data.

{% include "../../../../.gitbook/includes/feature-request.md" %}
