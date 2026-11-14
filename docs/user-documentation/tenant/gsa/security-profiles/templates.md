# Security Profile Templates

This page lists your Global Secure Access security profile templates. A security profile groups filtering policies, each with its own priority, and is applied to users by a Conditional Access policy. The template links filtering policy templates, so changing a filtering policy template changes every security profile that uses it.

A security profile filters nothing on its own: a Conditional Access policy has to use it. Deploying needs a Microsoft Entra Internet Access licence (included in Microsoft Entra Suite) in each tenant.

## Action Buttons

{% content-ref url="template.md" %}
[template.md](template.md)
{% endcontent-ref %}

## Table Details

| Column      | Description                                                                         |
| ----------- | ----------------------------------------------------------------------------------- |
| Name        | The template name. It is also the security profile name in each tenant.             |
| Priority    | The order the profile is processed in, from 100 to 64999. Lower numbers go first.   |
| State       | Whether the profile is enabled or disabled.                                         |
| Description | The description saved with the template.                                            |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Deploy Template</td><td>Opens the Deploy Security Profile drawer. Choose one or more tenants (or All Tenants) and select <strong>Deploy</strong>. Each tenant gets the security profile and its filtering policies created or updated to match the template, and the results list what changed in each tenant. A tenant is left unchanged when it has no Microsoft Entra Internet Access licence, or when the template clashes with something already there (for example another profile using the same priority, or two profiles with the template's name).</td><td>false</td></tr><tr><td>Edit Template</td><td>Opens <a data-mention href="template.md">template.md</a> for editing.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Saves the template to a community repository you can write to, together with the filtering policy templates it links. Importing it from the repository brings those too. Shown when the GitHub integration is enabled.</td><td>false</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. It is refused while a Conditional Access template still uses it, and the message names those templates. Profiles already deployed to tenants are not removed.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full template.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
