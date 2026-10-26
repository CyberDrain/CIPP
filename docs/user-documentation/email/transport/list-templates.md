# Transport Templates

This page lists the transport rule templates saved in CIPP, including a set of ready-made ones that ship with the product for common tasks such as blocking external auto-forwarding and stripping read receipts. Templates are stored in CIPP rather than in a tenant, and they are what the **Deploy Template** drawer offers you when it asks for a template. New templates are built by hand with the **New Template** button, or captured from a live rule with the **Create template based on rule** action on the [list-rules.md](list-rules.md "mention") page.

## Action Buttons

<details>

<summary>Deploy Template</summary>

Opens a drawer that deploys a transport rule to one or more tenants. Select the target tenants, then either pick a template from this list to fill in the **New-TransportRule parameters (JSON)** box or type the JSON in yourself, and click **Deploy Transport Rule**. If a rule of the same name already exists in a target tenant, that rule is updated to match the template instead of a second copy being added.

</details>

<details>

<summary>New Template</summary>

Opens the same editor as **New Transport Rule** on the Transport Rules page, without a tenant behind it. Fill in the name, comments, conditions, actions and exceptions as you would for a rule. There is no priority, because a template is not placed in any tenant's rule order. Users, groups, domains and connectors are typed in rather than picked from a tenant's directory.

Text values can contain CIPP variables such as `%tenantname%` or your own custom variables; type `%` in a text field to pick one. Variables are resolved for each tenant when the template is deployed, from this page, from the Transport Rule Template standard or from a baseline, so a rule named `%tenantname% - External tag` is created and checked under each tenant's own name.

</details>

## Table Details

| Column   | Description                                                                                                                            |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Name     | The template name, which is also the name given to the rule it creates.                                                                |
| Comments | The description saved with the template. Templates captured from a live rule inherit that rule's own comments, so this is often empty. |
| GUID     | The template's unique identifier, useful for telling apart two templates that share a name.                                            |

{% hint style="info" %}
The templates that ship with CIPP are always available. Deleting one removes it from the list until the page is next loaded, at which point it returns. Templates you have created yourself stay deleted.

The flyout shows a template's name, comments, and identifier. Use **Edit Template** to review or change the rule a template deploys. Changes to a template that ships with CIPP are overwritten when the page is next loaded, so build a changed copy with **New Template** instead.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the selected template in the editor described under <strong>New Template</strong>. Saving overwrites the template in place.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Commits the selected template to a GitHub repository you choose, using a commit message you supply. Greyed out unless the GitHub integration is set up and you have write access to at least one repository.</td><td>true</td></tr><tr><td>Delete Template</td><td>Removes the selected template from CIPP. Rules already deployed from the template keep working and are not changed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
