# App Policies

Lists the app protection and app configuration policies on the selected tenant, showing what type each policy is and who it is assigned to. App protection policies control how corporate data is handled inside managed apps, while app configuration policies push settings into those apps. Both families are listed together here.

## Action Buttons

{% include "../../../.gitbook/includes/deploy-policy-expand.md" %}

## Table Details

| Column                  | Description                                                                                                                                                                                                                                                                                                                                               |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name            | The name of the policy.                                                                                                                                                                                                                                                                                                                                   |
| Policy Type Name        | The kind of policy and the platform it applies to. App protection policies show as iOS App Protection, Android App Protection, Windows App Protection, Windows Information Protection (MDM) or App Configuration (MAM). App configuration policies show as iOS App Configuration, Android Enterprise App Configuration or Android for Work Configuration. |
| Policy Assignment       | The groups and broad targets the policy is assigned to. All Devices and All Licensed Users appear here where those targets are used.                                                                                                                                                                                                                      |
| Policy Exclude          | The groups excluded from the policy.                                                                                                                                                                                                                                                                                                                      |
| Last Modified Date Time | When the policy was last changed.                                                                                                                                                                                                                                                                                                                         |

A Policy Source column is also available from the column chooser, and appears in the row flyout. It distinguishes the two families the list is assembled from, showing AppProtection for a managed app policy and AppConfiguration for a mobile app configuration.

## Table Actions

{% include "../../../../.gitbook/includes/intune-actions.md" %}

## Deployment Status

The **More Info** flyout begins with a **Deployment Status** section, showing who the policy has reached in the same way as the User status page in the Microsoft Intune admin center. Above the table a chip for each status counts how many rows are in it.

App protection policies, Windows Information Protection policies and App Configuration (MAM) policies have no per-device status, so they show a **Users** tab only, with one row for each app registration the policy applies to. The other app configuration policies show both a **Devices** tab and a **Users** tab.

**Users**

| Column              | Description                                                                                                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| User Principal Name | The user's sign-in name.                                                                                                                                                       |
| User Name           | The user's display name.                                                                                                                                                       |
| Status              | For a policy with a **Users** tab only, Checked in, or the reason Intune has flagged the registration, for example Rooted device. Otherwise, the policy's status for the user. |
| Status Detail       | For a policy with a **Users** tab only, the app and the device it is registered on, with the device type. Otherwise not used.                                                  |
| Device Count        | The number of the user's devices the status covers. Not used for a policy with a **Users** tab only.                                                                           |
| Last Reported       | When the user's status was last reported. Empty where Intune does not report it.                                                                                               |

**Devices**

Shown for app configuration policies other than App Configuration (MAM).

| Column              | Description                                                                               |
| ------------------- | ----------------------------------------------------------------------------------------- |
| Device Name         | The name of the device.                                                                   |
| User Principal Name | The user associated with the device's status.                                             |
| Status              | The result of applying the policy on the device, for example succeeded, error or pending. |
| Status Detail       | Not used for app configuration policies.                                                  |
| Platform            | The device's model.                                                                       |
| Last Reported       | When the device last reported its status.                                                 |

{% include "../../../../.gitbook/includes/feature-request.md" %}
