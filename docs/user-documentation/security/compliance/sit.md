# Sensitive Information Types

Sensitive Information Types are the pattern matchers Purview uses to recognize sensitive content such as card numbers, national identifiers or your own organizational reference formats. DLP policies, auto labeling rules and sensitivity labels all point at them as detection conditions. This page lists the custom Sensitive Information Types published in the selected tenant, lets you inspect what each one actually detects, and lets you delete them or capture them as reusable templates.

{% hint style="info" %}
Microsoft's built-in Sensitive Information Types are filtered out of this list. Only types published by your organization, or by a third party other than Microsoft, are shown.
{% endhint %}

## Action Buttons

<details>

<summary>Deploy SIT</summary>

Opens a drawer that creates a Sensitive Information Type in one or more tenants from a template or from parameters you supply yourself.

| Field | Description |
| ----- | ----------- |
| Select Tenants | The tenants to create the type in. At least one is required, and you can pick several to deploy the same type across a group of customers in one go. |
| Select a template (optional) | Picks a saved Sensitive Information Type template. Choosing one fills **Parameters (JSON)** with that template's stored settings, which you can then edit before deploying. |
| Parameters (JSON) | The type's settings as JSON. Required. Two worked examples are shown in the field until you type into it: a simple form giving a name, description, regular expression, confidence level and proximity, where the rule pack is built for you, and an advanced form where you supply your own rule pack XML as base64. |

</details>

## Table Details

The properties returned are for the Exchange Online PowerShell command `Get-DlpSensitiveInformationType`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-dlpsensitiveinformationtype?view=exchange-ps).

Opening a row's Extended Info flyout also looks up the rule pack behind the type and shows both its parsed detection configuration and the raw rule pack XML, so you can see exactly what the type matches on. That detail is available for classic pattern based types, shown with a **Type** of `Entity`, and the flyout reports when a rule pack cannot be loaded.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Create template based on SIT</td><td>Saves the selected Sensitive Information Type as a template so it can be redeployed to other tenants.</td><td>false</td></tr><tr><td>Delete SIT</td><td>Permanently removes the selected Sensitive Information Type from the tenant.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
