# Sensitivity Labels

Sensitivity labels classify content and carry protection with it. Once a label is applied to a file, an email or a container, it enforces whatever is configured on it: encryption, content marking such as headers, footers and watermarks, and site and group protection. Label policies then publish labels to users. This page lists the sensitivity labels in the selected tenant, shows which policies publish each one, and lets you recolor, delete or capture them as reusable templates.

## Action Buttons

<details>

<summary>Deploy Sensitivity Label</summary>

Opens a drawer that creates a sensitivity label in one or more tenants from a template or from parameters you supply yourself.

| Field | Description |
| ----- | ----------- |
| Select Tenants | The tenants to create the label in. At least one is required, and you can pick several to deploy the same label across a group of customers in one go. |
| Select a template (optional) | Picks a saved sensitivity label template. Choosing one fills **Parameters (JSON)** with that template's stored settings, and also loads the template's color into **Label Color**. |
| Label Color (optional) | A color picker for the label. It accepts any hex color, where the Purview portal offers only its preset palette. A color picked here overrides any color set in the JSON below. Leave it empty to keep whatever the JSON specifies. |
| Parameters (JSON) | The label settings as JSON. Required. A worked example is shown in the field until you type into it, covering the display name, tooltip, content types, encryption settings, content marking and a nested `PolicyParams` block for the label policy that publishes it. |

</details>

## Table Details

| Column | Description |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Display Name                    | The label name as users see it in Office apps.                                                                 |
| Name                            | The label's internal name in Purview.                                                                          |
| Color                           | The label's custom color, read by CIPP from the label's `color` advanced setting. Empty when none is set.      |
| Content Type                    | What the label can be applied to, such as files and emails.                                                    |
| Encryption Enabled              | Whether the label applies encryption to content it is put on.                                                  |
| Content Marking Header Enabled  | Whether the label stamps a header onto content.                                                                |
| Content Marking Watermark Enabled | Whether the label stamps a watermark onto content.                                                           |
| Site And Group Protection Enabled | Whether the label carries container settings for sites, Teams and Microsoft 365 Groups.                      |
| Priority                        | The label's position in the label order.                                                                       |
| Disabled                        | Whether the label is switched off.                                                                             |

The Extended Info flyout adds the label's comment, tooltip, parent label, footer marking setting, and **Published In Policies**, which CIPP works out by matching the label against the tenant's label policies so you can see where a label is actually surfaced to users.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Create template based on label</td><td>Saves the selected label as a sensitivity label template so it can be redeployed to other tenants.</td><td>false</td></tr><tr><td>Set Label Color</td><td>Opens a color picker and applies the chosen color to the selected label. Any hex color is accepted, beyond the preset palette the Purview portal offers. Submitting an empty value clears a color that was set previously.</td><td>false</td></tr><tr><td>Delete Label</td><td>Permanently removes the selected label. A label that is published to users is also removed from the policies publishing it.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
