# Configuration Policies

Lists the configuration policies on the selected tenant, showing what type each policy is and who it is assigned to. Selecting a row opens a flyout with the policy's settings, which is useful for reviewing a policy in detail or copying its configuration into another system or script.

## Action Buttons

{% include "../../../.gitbook/includes/deploy-policy-expand.md" %}

## Table Details

| Column                  | Description                                                                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name            | The name of the policy.                                                                                                                         |
| Policy Type Name        | The kind of policy, for example Device Configuration, Administrative Templates, Compliance Policy or Endpoint Security.                         |
| Policy Assignment       | The groups and broad targets the policy is assigned to. All Devices, All Users and All Licenced Users appear here where those targets are used. |
| Policy Exclude          | The groups and broad targets excluded from the policy.                                                                                          |
| Description             | The description recorded against the policy.                                                                                                    |
| Last Modified Date Time | When the policy was last changed.                                                                                                               |

{% hint style="info" %}
The flyout for a Settings Catalog or Administrative Templates policy fetches the policy's settings along with Microsoft's own descriptions for each one, so the settings read as names rather than identifiers. This takes a moment to load, and other policy types show their stored details without the extra lookup.
{% endhint %}

## Table Actions

{% include "../../../../.gitbook/includes/intune-actions.md" %}

## Deployment Status

The **More Info** flyout begins with a **Deployment Status** section, showing how the policy has deployed in the same way as the Device status and User status pages in the Microsoft Intune admin center. The section has a **Devices** tab and a **Users** tab, each labelled with its number of rows, and above the table a chip for each status counts how many rows are in it. The policy's own settings follow below the section.

**Devices**

| Column              | Description                                                                                         |
| ------------------- | --------------------------------------------------------------------------------------------------- |
| Device Name         | The name of the device.                                                                             |
| User Principal Name | The user associated with the device's status.                                                       |
| Status              | The result of applying the policy on the device, for example succeeded, error, conflict or pending. |
| Status Detail       | Not used for configuration policies.                                                                |
| Platform            | The device's platform. For device configuration profiles, the device's model.                       |
| Last Reported       | When the device last reported its status.                                                           |

**Users**

| Column              | Description                                                                      |
| ------------------- | -------------------------------------------------------------------------------- |
| User Principal Name | The user's sign-in name.                                                         |
| User Name           | The user's display name.                                                         |
| Status              | The policy's status for the user.                                                |
| Status Detail       | Not used for configuration policies.                                             |
| Device Count        | The number of the user's devices the status covers.                              |
| Last Reported       | When the user's status was last reported. Empty where Intune does not report it. |

For settings catalog policies, administrative templates and endpoint security policies, Intune reports devices only, so the **Users** tab is built from the device rows: one row per user, carrying the worst status across that user's devices. Devices with no user are grouped into a single row named **No user**. For device configuration profiles, a user row with no user principal name is Intune's system account, which covers device-targeted check-ins.

{% hint style="info" %}
Windows feature, quality and driver update profiles and hardware configurations have no per-device status in Intune, so their flyout says that Intune has no deployment status for this type.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
