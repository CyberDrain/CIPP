# Sensitivity Label Templates

Sensitivity label templates are saved label configurations held in CIPP rather than in a tenant, so a label you have settled on can be deployed to any number of customers without rebuilding it each time. Templates get here in three ways: capture one from a live label with **Create template based on label** on the Sensitivity Labels page, author one from JSON in the deploy drawer, or import one from a community repository.

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

<details>

<summary>Browse Catalog</summary>

Opens a drawer listing the sensitivity label templates published in the community repositories you have configured, so you can bring one into CIPP.

| Field | Description |
| ----- | ----------- |
| Search Templates | Narrows the list by template name, category or repository. |
| Repository | Restricts the list to chosen repositories. Shown once you have more than one repository configured. |
| Category | Restricts the list to chosen categories. Shown once the available templates span more than one category. |
| Card and list view | Switches between template cards and a compact list. |
| All, Not Imported, Imported, Updates | Filters by import state. **Updates** narrows to templates you already imported that have since changed upstream. |
| Select all | Selects every template currently listed, for importing in one go. |
| Force re-import | Imports a template again even when CIPP already holds it, overwriting the copy you have. |
| Import Selected | Imports everything you have ticked. |

Each template also carries its own **Preview** and **Import** buttons, and is chipped **Imported** or **Update Available** so you can see its state at a glance.

{% hint style="info" %}
Be sure to check out [community-repos](../../tools/community-repos/ "mention") for more on setting up repositories.
{% endhint %}

</details>

## Table Details

| Column | Description |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| Display Name       | The label name users will see in Office apps once the template is deployed.                       |
| Name               | The label's internal name in Purview.                                                             |
| Comment            | The description saved with the template.                                                          |
| Content Type       | What the label will be applicable to, such as files and emails.                                   |
| Encryption Enabled | Whether the label will apply encryption to content it is put on.                                  |
| GUID               | CIPP's identifier for the template. Quote it when raising a support request about a specific template. |

{% hint style="info" %}
A template captured from a live label has its rights management template identifiers stripped, because those only mean anything in the tenant the label came from. The same applies to the parent label: CIPP stores the parent's name alongside it and matches the parent again by name in whichever tenant you deploy to.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Save to GitHub</td><td>Publishes the selected template to a repository you have write access to, prompting for the repository and a commit message. Greyed out unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Removes the selected template from CIPP. Labels already deployed from it are unaffected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
