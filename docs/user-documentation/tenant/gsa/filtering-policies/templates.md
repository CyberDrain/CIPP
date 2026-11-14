# Filtering Policy Templates

This page lists your Global Secure Access filtering policy templates. A filtering policy blocks or allows web traffic by web category, domain or URL. A template is saved once in CIPP and linked from security profile templates, so a change to the template reaches every tenant the profile is deployed to.

Filtering policies only take effect through a security profile, and a security profile only applies to users through a Conditional Access policy (or the tenant's baseline profile). Web content filtering needs a Microsoft Entra Internet Access licence, which is included in Microsoft Entra Suite.

## Action Buttons

{% content-ref url="template.md" %}
[template.md](template.md)
{% endcontent-ref %}

## Table Details

| Column      | Description                                                         |
| ----------- | ------------------------------------------------------------------- |
| Name        | The template name. It is also the policy name in each tenant.       |
| Action      | Whether traffic that matches a rule is blocked or allowed.          |
| Description | The description saved with the template.                            |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Deploy Template</td><td>Opens the Deploy Filtering Policy drawer. Choose one or more tenants (or All Tenants) and select <strong>Deploy</strong>. Each tenant gets the policy created, or the policy with the same name updated to match the template. A filtering policy blocks or allows nothing until a security profile links it. A tenant without a Microsoft Entra Internet Access licence is left unchanged.</td><td>false</td></tr><tr><td>Edit Template</td><td>Opens <a data-mention href="template.md">template.md</a> for editing.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Saves the template to a community repository you can write to. Shown when the GitHub integration is enabled.</td><td>false</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. It is refused while a security profile template still links it, and the message names those templates. Policies already deployed to tenants are not removed.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full template.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
