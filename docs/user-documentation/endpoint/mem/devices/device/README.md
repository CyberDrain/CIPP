# View Device

The View Device page shows everything CIPP knows about a single Intune-managed device and is where you act on that device individually. It brings together the device's own details, the compliance, configuration, and enrollment policies applied to it, the applications detected on it, the users associated with it, the groups it belongs to, and the actions recently sent to it. The full set of device actions is available from the page header, so a device can be synced, wiped, or renamed without returning to the device list.

The page header shows the device's name, with copyable chips for the device name and device ID, how long ago the device last synced, and a **View in Intune** link that opens the device in the Microsoft Intune admin center.

The page has two tabs. **Overview**, described on this page, holds the sections below. [Remediations](remediations.md) lists the remediation scripts that have run on the device and lets you run one again.

## Device Actions

The actions available on the [.](../ "mention") page are available here from the page header, applied to this device alone. The two navigation actions from that page, View Device and View in Intune, are not repeated in the menu, since the header already provides the Intune link and you are on the device page.

## Device Details

| Field            | Description                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------- |
| Device Name      | The name of the device.                                                                                       |
| Device ID        | The device's identifier in Intune.                                                                            |
| Operating System | The device's operating system and version.                                                                    |
| Manufacturer     | The device's manufacturer.                                                                                    |
| Model            | The device's model.                                                                                           |
| Serial Number    | The device's serial number.                                                                                   |
| Compliance State | Whether the device currently meets the compliance policies applied to it.                                     |
| Grace period expires | When the device will leave the compliance grace period and become non-compliant. Only shown when Intune reports a grace period expiry. |
| Enrolled Date    | When the device was enrolled in Intune.                                                                       |
| Last Sync        | When the device last checked in with Intune.                                                                  |
| Owner Type       | Whether the device is company owned or personal.                                                              |
| Enrollment Type  | How the device was enrolled into Intune.                                                                      |
| Primary User     | The user the device is assigned to. Only shown where one is set.                                              |
| Storage          | Free space against total capacity, with the percentage used. Only shown where the device reports its storage. |

{% hint style="info" %}
A refresh control on this card reloads the device's details and the sections below it.
{% endhint %}

## Policies

Brings the policies applied to the device together in one section, using the same reports as the device page in the Microsoft Intune admin center. Each group below is a single entry with a summary count and an overall status, and expanding it shows a table with one row per policy. If one group fails to load, that entry shows the error and the other groups still load.

For compliance and configuration policies, **More Info** on a row opens a drawer with the individual setting states for that policy: the setting name, state, current value, contributing sources, and any error description. The drawer defaults to failing settings, and **Show all settings** includes the rest. Setting-level results are not available for every policy type, and the drawer says so where they are missing.

**Compliance Policies**

The summary shows how many compliance policies apply and how many the device is not compliant with.

| Column              | Description                                               |
| ------------------- | --------------------------------------------------------- |
| Policy Name         | The name of the compliance policy.                        |
| Status              | The device's compliance state against the policy.         |
| User Principal Name | The user the policy was evaluated for.                    |
| Last Contact Date Time | When the device last reported its state for the policy. |

**Configuration Policies**

Covers device configuration profiles, settings catalog policies, administrative templates, and endpoint security policies. The summary shows how many apply, how many have errors or conflicts, and how many are in any other state, such as pending.

| Column                 | Description                                                   |
| ---------------------- | ------------------------------------------------------------- |
| Policy Name            | The name of the policy.                                       |
| Status                 | The result of applying the policy, for example succeeded, error, or conflict. |
| Policy Type            | The kind of policy, for example a settings catalog policy.    |
| Last Reported Date Time | When the device last reported its state for the policy.      |

**Enrollment Configurations**

Lists the enrollment configurations that applied when the device enrolled. This group appears only when the device has enrollment configurations to show.

| Column       | Description                                 |
| ------------ | ------------------------------------------- |
| Profile Name | The name of the enrollment configuration.   |
| Policy Type  | The kind of enrollment configuration.       |

## Detected Applications

Reports the applications Intune has detected on the device, with a count in the section header. Expanding the entry shows the full list.

| Column       | Description                           |
| ------------ | ------------------------------------- |
| Display Name | The name of the detected application. |
| Version      | The version detected on the device.   |
| Platform     | The platform the application runs on. |

## Associated Users

Lists the users associated with the device. Expanding the entry shows the full list, and a **View User** action on each row opens that user's page in CIPP.

| Column              | Description               |
| ------------------- | ------------------------- |
| Display Name        | The user's name.          |
| User Principal Name | The user's sign-in name.  |
| Mail                | The user's email address. |

## Memberships

Lists the groups the device belongs to, including those it inherits through nested groups. Expanding the entry shows the full list, and an **Edit Group** action on each row opens that group for editing.

| Column           | Description                            |
| ---------------- | -------------------------------------- |
| Display Name     | The name of the group.                 |
| Group Types      | The group's type.                      |
| Security Enabled | Whether the group is security enabled. |
| Mail Enabled     | Whether the group is mail enabled.     |

{% hint style="info" %}
Group membership is read against the device's Entra ID object rather than its Intune record. A device that is not joined to Entra ID, such as one enrolled through a co-management or MDM-only path, reports no group memberships here even where it is managed by Intune. Only groups are listed, so directory roles and administrative units the device object belongs to are left out.
{% endhint %}

## Action History

Lists the actions sent to the device, newest first, such as syncs, reboots, and remediation runs. The summary shows how many actions are recorded and how many are pending or failed. Only the action and its progress are shown, so results that carry a secret, such as a reset passcode, are not displayed here.

| Column                 | Description                                        |
| ---------------------- | -------------------------------------------------- |
| Action Name            | The action that was sent to the device.            |
| Action State           | The action's progress, for example pending, done, or failed. |
| Start Date Time        | When the action was sent.                          |
| Last Updated Date Time | When the action's state last changed.              |

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
