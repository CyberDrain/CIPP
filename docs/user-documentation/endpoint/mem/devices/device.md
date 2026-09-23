# View Device

The View Device page shows everything CIPP knows about a single Intune-managed device and is where you act on that device individually. It brings together the device's own details, the compliance and configuration policies applied to it, the applications detected on it, the users associated with it, and the groups it belongs to. The full set of device actions is available from the page header, so a device can be synced, wiped, or renamed without returning to the device list.

The page header shows the device's name, with copyable chips for the device name and device ID, how long ago the device last synced, and a **View in Intune** link that opens the device in the Microsoft Intune admin center.

## Device Actions

The actions available on the [.](./ "mention") page are available here from the page header, applied to this device alone. The two navigation actions from that page, View Device and View in Intune, are not repeated in the menu, since the header already provides the Intune link and you are on the device page.

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

## Compliance Policies

Lists the compliance policies applied to the device, one entry per policy. Each entry shows the policy's name and the state the device is in against it, marked as compliant or flagged for attention. Expanding an entry shows the policy's setting count and loads the individual setting states for that policy, including the setting name, state, current value, contributing sources, and any error description. The list defaults to non-compliant, error, and conflict settings; use **Show all settings** to include compliant and not-applicable rows.

## Configuration Policies

Lists the configuration policies applied to the device in the same form as compliance policies: the policy name, the device's state against it, and on expansion the setting count plus the per-setting states with the same failures-first filter and sources column.

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

{% include "../../../../../.gitbook/includes/feature-request.md" %}
