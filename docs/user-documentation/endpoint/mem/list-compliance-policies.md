# Compliance Policies

Lists the device compliance policies on the selected tenant, showing what type each policy is and who it is assigned to. Compliance policies define the conditions a device must meet to be considered compliant, which conditional access and other controls can then act on.

## Action Buttons

{% include "../../../.gitbook/includes/deploy-policy-expand.md" %}

## Table Details

| Column                  | Description                                                                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name            | The name of the policy.                                                                                                                      |
| Policy Type Name        | The platform the policy applies to, for example Windows 10/11 Compliance, iOS Compliance, macOS Compliance or Android Enterprise Compliance. |
| Policy Assignment       | The groups and broad targets the policy is assigned to. All Devices and All Licensed Users appear here where those targets are used.         |
| Policy Exclude          | The groups excluded from the policy.                                                                                                         |
| Description             | The description recorded against the policy.                                                                                                 |
| Last Modified Date Time | When the policy was last changed.                                                                                                            |

The remaining properties, available from the column chooser and in the row flyout, are those of the Graph resource type `deviceCompliancePolicy`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-shared-devicecompliancepolicy?view=graph-rest-beta#properties).

## Table Actions

{% include "../../../../.gitbook/includes/intune-actions.md" %}

## Deployment Status

The **More Info** flyout begins with a **Deployment Status** section, showing how the policy has deployed in the same way as the Device status and User status pages in the Microsoft Intune admin center. The section has a **Devices** tab and a **Users** tab, each labelled with its number of rows, and above the table a chip for each status counts how many rows are in it.

**Devices**

| Column              | Description                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------- |
| Device Name         | The name of the device.                                                                                  |
| User Principal Name | The user associated with the device's status.                                                            |
| Status              | The device's compliance with the policy, for example compliant, non compliant, error or in grace period. |
| Status Detail       | Not used for compliance policies.                                                                        |
| Platform            | The device's model.                                                                                      |
| Last Reported       | When the device last reported its status.                                                                |

**Users**

| Column              | Description                                                                      |
| ------------------- | -------------------------------------------------------------------------------- |
| User Principal Name | The user's sign-in name.                                                         |
| User Name           | The user's display name.                                                         |
| Status              | The user's compliance with the policy.                                           |
| Status Detail       | Not used for compliance policies.                                                |
| Device Count        | The number of the user's devices the status covers.                              |
| Last Reported       | When the user's status was last reported. Empty where Intune does not report it. |

A user row named **System account** covers the policy's device-targeted check-ins rather than a signed-in user.

{% include "../../../../.gitbook/includes/feature-request.md" %}
