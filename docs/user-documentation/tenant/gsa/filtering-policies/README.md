# Filtering Policies

This page lists the Global Secure Access web content filtering policies in the selected tenant, read live from the tenant. A filtering policy blocks or allows web traffic by web category, domain or URL, and takes effect through the security profiles that link it.

The **Templates** tab holds the filtering policy templates you deploy to tenants through security profile templates.

{% content-ref url="templates.md" %}
[templates.md](templates.md)
{% endcontent-ref %}

## Table Details

| Column            | Description                                                         |
| ----------------- | ------------------------------------------------------------------- |
| Name              | The policy name.                                                    |
| Action            | Whether traffic that matches a rule is blocked or allowed.          |
| Description       | The policy description.                                             |
| Security Profiles | The security profiles in this tenant that link the policy.          |

## Page Actions

<table><thead><tr><th>Action</th><th>Description</th></tr></thead><tbody><tr><td>Add Policy</td><td>Opens the <a href="edit.md">editor</a> to create a new filtering policy in the selected tenant.</td></tr><tr><td>Deploy Template</td><td>Opens the deploy drawer with the selected tenant already chosen. Pick a filtering policy template and select <strong>Deploy</strong>; you can add more tenants first.</td></tr></tbody></table>

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Policy</td><td>Opens the policy in the <a href="edit.md">editor</a>.</td><td>false</td></tr><tr><td>Save as Template</td><td>Saves the policy as a filtering policy template with the same name, so it can be deployed to other tenants. It is refused if a template with that name already exists.</td><td>false</td></tr><tr><td>Delete Policy</td><td>Deletes the policy from the tenant. It is refused while a security profile links the policy, and the message names those profiles.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full policy, including its rules.</td><td>false</td></tr></tbody></table>
