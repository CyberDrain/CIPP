# Configuration Policies

Lists the configuration policies on the selected tenant, showing what type each policy is and who it is assigned to. Selecting a row opens a flyout with the policy's settings, which is useful for reviewing a policy in detail or copying its configuration into another system or script.

## Action Buttons

{% include "../../../.gitbook/includes/deploy-policy-expand.md" %}

## Table Details

| Column                  | Description                                                                                                                                     |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name            | The name of the policy.                                                                                                                         |
| Policy Type Name        | The kind of policy, for example Device Configuration, Administrative Templates, Compliance Policy or Endpoint Security.                         |
| Policy Assignment       | The groups and broad targets the policy is assigned to. All Devices, All Users and All Licensed Users appear here where those targets are used. |
| Policy Exclude          | The groups and broad targets excluded from the policy.                                                                                          |
| Description             | The description recorded against the policy.                                                                                                    |
| Last Modified Date Time | When the policy was last changed.                                                                                                               |

{% hint style="info" %}
The flyout for a Settings Catalog or Administrative Templates policy fetches the policy's settings along with Microsoft's own descriptions for each one, so the settings read as names rather than identifiers. This takes a moment to load, and other policy types show their stored details without the extra lookup.
{% endhint %}

## Table Actions

{% include "../../../../.gitbook/includes/intune-actions.md" %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
