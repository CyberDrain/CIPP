# Connector Templates

This page lists the Exchange connector templates saved in CIPP. Templates are stored in CIPP rather than in a tenant, and they are what the **Deploy Connector** drawer offers you when it asks for a template. New templates are added with the **Create template based on connector** action on the [list-connectors.md](list-connectors.md "mention") page.

## Action Buttons

<details>

<summary>Deploy Connector</summary>

Opens a drawer that creates a connector in one or more tenants. Select the target tenants, then either pick a template from this list to fill in the **Parameters (JSON)** box or type the JSON in yourself, and click **Deploy Connector**. The result for each tenant is shown in the drawer, and your tenant selection is kept so you can deploy another.

</details>

## Table Details

| Column            | Description                                                                                                            |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Name              | The template name, which is also the name given to the connector it creates.                                           |
| Cippconnectortype | Whether the template creates a connector for mail arriving at the organization (`Inbound`) or leaving it (`Outbound`). |
| GUID              | The template's unique identifier, useful for telling apart two templates that share a name.                            |

The Extended Info flyout on this page is a **Connector Template Details** card showing every setting the template holds, rather than only the three columns above. Which settings appear depends on the direction: outbound templates cover options such as smart hosts, TLS settings, and recipient domains, while inbound templates cover options such as sender domains, sender IP addresses, and the required sender certificate name.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Save to GitHub</td><td>Commits the selected template to a GitHub repository you choose, using a commit message you supply. Greyed out unless the GitHub integration is set up and you have write access to at least one repository.</td><td>true</td></tr><tr><td>Delete Template</td><td>Removes the selected template from CIPP. Connectors already deployed from the template keep working and are not changed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
