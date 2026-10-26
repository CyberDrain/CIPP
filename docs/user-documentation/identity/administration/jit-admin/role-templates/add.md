# Add JIT Role Template

Here you can create a JIT Role Template. Give the template a name, select the directory roles it should allow, and hit save.

| Option        | Description                                                                                                                             |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Template Name | A unique name for the template.                                                                                                          |
| Allowed Roles | The Entra ID directory roles this template permits. CIPP custom roles assigned this template may only grant these roles via JIT Admin. |

{% hint style="info" %}
The template only takes effect once it is assigned to a CIPP custom role on the [Add Role](../../../../cipp/advanced/authentication/cipp-roles/add.md) page. A custom role with no template assigned can still grant all roles.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
