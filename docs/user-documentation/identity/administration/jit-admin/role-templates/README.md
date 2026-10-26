# JIT Role Templates

A JIT Role Template is a named allow-list of Entra ID directory roles. Assigning one to a [CIPP custom role](../../../../cipp/advanced/authentication/cipp-roles/README.md) restricts members of that role to only grant the roles in the template when creating a JIT Admin, and they can only see existing JIT Admins whose roles fall entirely within the template.

{% hint style="info" %}
Restriction combines the same way CIPP handles multiple custom roles elsewhere - restrictively, not additively. A custom role with no template assigned does not restrict anything on its own, but as soon as a user holds a role that has a template they are restricted, and their allowed roles are the intersection of every template they hold. An untemplated role cannot be used to bypass a template assigned alongside it. Admin and Super Admin users are unaffected, and if no template is assigned anywhere nothing changes, so existing configurations are not disturbed until you assign one.
{% endhint %}

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

## Table Details

| Column        | Description                                              |
| ------------- | --------------------------------------------------------- |
| Template Name | The name of the template given at creation or last edit. |
| Roles         | The directory roles included in this allow-list.         |
| Created By    | The user that created the template.                      |
| Created Date  | The date the template was created.                        |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the selected template for editing in <a data-mention href="edit.md">edit.md</a>.</td><td>false</td></tr><tr><td>Delete Template</td><td>Deletes the template. A custom role still assigned this template is not reverted to unrestricted - it fails closed, so its members can no longer grant or see any roles via JIT Admin until a different template is assigned or the assignment is cleared.</td><td>false</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
