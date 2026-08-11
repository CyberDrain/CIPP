# Edit Template

Opens a saved Intune policy template so its name, description and settings can be changed. Edits are stored against the template in CIPP, so they take effect the next time the template is deployed rather than changing any policy already in a tenant.

{% hint style="warning" %}
Only templates that are not synced to a community repository can be edited. A synced template must be cloned first, which breaks its link to the repository and makes the copy editable.
{% endhint %}

## Template details

| Field         | Description                                                                                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Template Name | The name of the template. Required. This is also the name the deployed policy takes, and the name CIPP matches on when deciding whether to overwrite an existing policy. |
| Description   | The description recorded against the template.                                                                                                                           |

The template's type is shown alongside the card heading.

## Policy settings

Lists the template's settings as editable fields, grouped into the sections Intune itself organizes them under. Each setting is rendered according to what it accepts: a true or false switch, a list of the options the setting allows, a list of values, or a free text or numeric field.

Under each setting, **Raw values** expands to show the setting's definition identifier, the exact values it accepts, and the value currently stored. This is the value written into the policy, which is not always the same as the friendly label shown in the field.

CIPP custom variables appear in the field's dropdown alongside the setting's own options. Choosing one stores the variable rather than a fixed value, and it is resolved per tenant when the template is deployed, so one template can carry a different value for each customer. The variable has to resolve to what the setting accepts, and where the type does not match the field says so.

{% hint style="warning" %}
Changing a setting that has other settings nested beneath it does not update those nested settings. They still hold the values belonging to the option that was originally selected, and CIPP flags this when it happens.
{% endhint %}

Some templates cannot have their settings edited here:

| Situation                                   | What happens                                                                                                                    |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Administrative Templates                    | The settings are resolved against a tenant and cannot be presented as fields. The name and description remain editable.         |
| The stored policy is not valid JSON         | An error is shown and nothing can be edited.                                                                                    |
| The Intune setting catalog cannot be loaded | Settings appear under their definition identifiers with no option lists to pick from. Values changed are still saved correctly. |

{% hint style="info" %}
Settings the editor does not present as fields are left exactly as they were stored. Saving a template only changes the values bound to a field, so nothing else in the underlying policy is rewritten.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
