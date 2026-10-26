# Role Templates

This page lists the GDAP role templates you have created. A template is a named set of admin roles, and it is what you select when generating an invite or onboarding a tenant, so every relationship is built with a consistent set of permissions.

Each role in a template is backed by a security group in your partner tenant. CIPP creates those groups for you as you build the template, so this page is the only one you normally need: add your technicians to the groups and they gain the matching delegated access in your customer tenants.

If you have no templates yet, the page offers to create the **CIPP Defaults** template, which contains the 15 roles listed on the [recommended-roles.md](../../../../setup/maintaining-cipp/recommended-roles.md "mention") page, or to build a custom one. If you have templates but none named `CIPP Defaults`, a warning offers to create it - so the prompt returns if you delete or rename that template.

Use **Add Template** to create a template via [add.md](add.md "mention"), or **Group Mappings** to review the underlying role-to-group mappings on [README.md](mappings/README.md "mention").

## Table Details

| Column         | Description                                                                              |
| -------------- | ---------------------------------------------------------------------------------------- |
| Template Id    | The name of the template. This is the value you select when creating invites and onboarding tenants. |
| Roles          | The admin roles the template grants.                                                     |
| Group Mappings | How many security groups the template maps to.                                           |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens <a data-mention href="edit.md">edit.md</a> so you can rename it or change which roles it contains.</td><td>false</td></tr><tr><td>Clone Template</td><td>Copies the template's role mappings to a new template under a name you provide.</td><td>false</td></tr><tr><td>Create Invite</td><td>Opens the invite form with this template preselected.</td><td>false</td></tr><tr><td>Delete Template</td><td>Removes the template from CIPP. The underlying group mappings and security groups are not deleted, and existing relationships built from the template are not changed.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
