# Policy Failures

Lists the Intune configuration policies on the selected tenant that have at least one device in an error or conflict state, matching the assignment failures view in the Microsoft Intune admin center. Settings catalog policies, device configuration profiles, administrative templates and endpoint security policies are all covered. Use it to find which policies are failing and on which devices, then drill into a policy to see the settings at fault and the other policies a conflicting setting clashes with.

## Table Details

| Column           | Description                                                                    |
| ---------------- | ------------------------------------------------------------------------------ |
| Display Name     | The name of the policy.                                                        |
| Policy Type Name | The kind of policy, as Intune names it, for example a settings catalog policy. |
| Platform         | The platform the policy applies to.                                            |
| Error Devices    | The number of devices on which the policy is in an error state.                |
| Conflict Devices | The number of devices on which the policy conflicts with another policy.       |

Policies with no devices in error or conflict are left out, so an empty table means nothing is failing.

## Policy Details

Selecting a row opens a flyout with the policy's details and two tables for that policy. If part of the detail cannot be loaded, a warning above the tables says which part, and the rest still loads.

**Failing Settings**

One row per setting in the policy that is in error or conflict on at least one device.

| Column               | Description                                                                                                                                                                                                                                                                                               |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setting Name         | The setting that is failing.                                                                                                                                                                                                                                                                              |
| Error Devices        | The number of devices on which the setting is in an error state.                                                                                                                                                                                                                                          |
| Conflict Devices     | The number of devices on which the setting conflicts with another policy.                                                                                                                                                                                                                                 |
| Conflicting Policies | The other policies that set the same setting on the conflicting devices. Filled in for device configuration profiles and settings catalog policies only. For a settings catalog policy, only other settings catalog policies are named, so a clash with a device configuration profile leaves this empty. |

**Devices**

One row for each device on which the policy is in error or conflict.

| Column                        | Description                                                  |
| ----------------------------- | ------------------------------------------------------------ |
| Device Name                   | The name of the device.                                      |
| UPN                           | The user the policy was evaluated for on the device.         |
| Report Status                 | Whether the policy is in error or in conflict on the device. |
| Pspdpu Last Modified Time Utc | When the device last reported its state for the policy.      |

Each device row offers **View Device**, which opens the device's [View Device](devices/device/README.md) page in CIPP, and **View in Intune**, which opens the device in the Microsoft Intune admin center in a new tab.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Open Intune</td><td>Opens the selected tenant in the Microsoft Intune admin center in a new tab.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
